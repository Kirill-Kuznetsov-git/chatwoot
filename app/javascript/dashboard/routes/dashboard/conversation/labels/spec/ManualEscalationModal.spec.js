import { mount } from '@vue/test-utils';
import ManualEscalationModal from '../ManualEscalationModal.vue';

const details = {
  title: 'Automatic topic',
  title_override: '',
  reason: '',
  reasons: ['Other'],
  max_length: 150,
};
const makeWrapper = () =>
  mount(ManualEscalationModal, {
    props: { details },
    global: {
      stubs: {
        Dialog: {
          template:
            '<div><slot /><button @click="$emit(\'confirm\')">Confirm</button><button @click="$emit(\'close\')">Cancel</button></div>',
          methods: { open() {} },
        },
      },
      mocks: { $t: key => key },
    },
  });

describe('ManualEscalationModal', () => {
  it('shows the automatic title but submits an empty override until edited', async () => {
    const wrapper = makeWrapper();
    expect(wrapper.find('input').element.value).toBe('Automatic topic');
    await wrapper.findAll('button')[0].trigger('click');
    expect(wrapper.emitted('confirm')[0]).toEqual([{ title: '', reason: '' }]);
  });

  it('submits edited title and optional reason, and clearing means automatic', async () => {
    const wrapper = makeWrapper();
    await wrapper.find('input').setValue('New topic');
    await wrapper.find('select').setValue('Other');
    await wrapper.findAll('button')[0].trigger('click');
    expect(wrapper.emitted('confirm')[0]).toEqual([
      { title: 'New topic', reason: 'Other' },
    ]);
    await wrapper.find('input').setValue('');
    await wrapper.findAll('button')[0].trigger('click');
    expect(wrapper.emitted('confirm')[1]).toEqual([
      { title: '', reason: 'Other' },
    ]);
  });

  it('accepts 150 Unicode characters, rejects 151 and multiline input', async () => {
    const wrapper = makeWrapper();
    await wrapper.find('input').setValue('🦊'.repeat(150));
    await wrapper.findAll('button')[0].trigger('click');
    expect(wrapper.emitted('confirm')).toHaveLength(1);
    await wrapper.find('input').setValue('x'.repeat(151));
    await wrapper.findAll('button')[0].trigger('click');
    expect(wrapper.emitted('confirm')).toHaveLength(1);
  });

  it('cancel does not confirm', async () => {
    const wrapper = makeWrapper();
    await wrapper.findAll('button')[1].trigger('click');
    expect(wrapper.emitted('cancel')).toHaveLength(1);
    expect(wrapper.emitted('confirm')).toBeUndefined();
  });
});
