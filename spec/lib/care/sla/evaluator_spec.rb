require 'rails_helper'

describe Care::Sla::Evaluator do
  let(:config) { Care::Queue::Config.new(Care::Queue::Defaults::SETTINGS, version: 1, source: 'test') }
  let(:klass) { config.class_for('vip') } # fr 30 / nr 60 / res 720 мин, риск с 80 %
  let(:started_at) { Time.zone.parse('2026-09-08 10:00:00 UTC') }
  let(:tracker) { Care::SlaTracker.new(started_at: started_at) }
  let(:conversation_class) do
    Struct.new(:first_reply_created_at, :waiting_since, :status) do
      def resolved?
        status == 'resolved'
      end
    end
  end
  let(:conversation) { conversation_class.new(nil, nil, 'open') }

  def evaluate(at:, conv: conversation, klass_override: klass)
    described_class.new(tracker, conv, klass_override, config, now: at).call
  end

  it 'first response: ok → at_risk (80 %) → breached, due = started_at + target' do
    expect(evaluate(at: started_at + 10.minutes)).to have_attributes(fr_state: 'ok', fr_due_at: started_at + 30.minutes)
    expect(evaluate(at: started_at + 24.minutes).fr_state).to eq('at_risk')
    expect(evaluate(at: started_at + 30.minutes).fr_state).to eq('breached')
  end

  it 'first response met in time, or breached when the human replied late; a reply before handoff counts at handoff' do
    on_time = conversation_class.new(started_at + 20.minutes, nil, 'open')
    expect(evaluate(at: started_at + 2.hours, conv: on_time)).to have_attributes(fr_state: 'met', first_response_at: started_at + 20.minutes)

    late = conversation_class.new(started_at + 45.minutes, nil, 'open')
    expect(evaluate(at: started_at + 2.hours, conv: late).fr_state).to eq('breached')

    before_handoff = conversation_class.new(started_at - 5.minutes, nil, 'open')
    expect(evaluate(at: started_at + 1.minute, conv: before_handoff)).to have_attributes(fr_state: 'met', first_response_at: started_at)
  end

  it 'first response stops at resolution when nobody from the team replied: ok if resolved in time, breached otherwise' do
    resolved = conversation_class.new(nil, nil, 'resolved')
    tracker.resolved_at = started_at + 20.minutes
    expect(evaluate(at: started_at + 2.hours, conv: resolved).fr_state).to eq('ok')

    tracker.resolved_at = started_at + 40.minutes
    expect(evaluate(at: started_at + 2.hours, conv: resolved).fr_state).to eq('breached')
  end

  it 'next response follows waiting_since and is ok while nobody is waiting' do
    expect(evaluate(at: started_at + 10.minutes)).to have_attributes(nr_state: 'ok', nr_anchor_at: nil, nr_due_at: nil)

    waiting = conversation_class.new(nil, started_at + 5.minutes, 'open')
    expect(evaluate(at: started_at + 50.minutes, conv: waiting)).to have_attributes(nr_state: 'ok', nr_due_at: started_at + 65.minutes)
    expect(evaluate(at: started_at + 54.minutes, conv: waiting).nr_state).to eq('at_risk') # риск с 80 % окна: +5 + 48
    expect(evaluate(at: started_at + 66.minutes, conv: waiting).nr_state).to eq('breached')

    resolved_waiting = conversation_class.new(nil, started_at + 5.minutes, 'resolved')
    expect(evaluate(at: started_at + 66.minutes, conv: resolved_waiting).nr_state).to eq('ok')
  end

  it 'resolution counts from handoff (or from reopen) until resolved' do
    expect(evaluate(at: started_at + 11.hours).res_state).to eq('at_risk')
    expect(evaluate(at: started_at + 13.hours).res_state).to eq('breached')

    resolved = conversation_class.new(nil, nil, 'resolved')
    tracker.resolved_at = started_at + 3.hours
    expect(evaluate(at: started_at + 20.hours, conv: resolved).res_state).to eq('met')

    tracker.resolved_at = nil # ещё не зафиксирован — берём now
    expect(evaluate(at: started_at + 13.hours, conv: resolved).res_state).to eq('breached')

    tracker.reopened_at = started_at + 20.hours
    expect(evaluate(at: started_at + 21.hours)).to have_attributes(res_state: 'ok', res_due_at: started_at + 32.hours)
  end

  it 'has no clocks for classes without SLA or without a target' do
    silent = klass.dup.tap { |k| k.sla_enabled = false }
    expect(evaluate(at: started_at + 5.hours, klass_override: silent)).to have_attributes(fr_state: 'none', nr_state: 'none', res_state: 'none')

    no_res = klass.dup.tap { |k| k.resolution_minutes = nil }
    expect(evaluate(at: started_at + 5.hours, klass_override: no_res)).to have_attributes(fr_state: 'breached', res_state: 'none')
  end
end
