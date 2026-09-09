require 'rails_helper'

RSpec.describe Internal::RemoveStaleContactInboxesJob do
  describe '#perform' do
    it 'runs the service' do
      service = instance_double(Internal::RemoveStaleContactInboxesService, perform: 0)
      allow(Internal::RemoveStaleContactInboxesService).to receive(:new).and_return(service)

      described_class.perform_now

      expect(service).to have_received(:perform)
    end

    it 'is scheduled on the scheduled_jobs queue' do
      expect(described_class.new.queue_name).to eq('scheduled_jobs')
    end
  end
end
