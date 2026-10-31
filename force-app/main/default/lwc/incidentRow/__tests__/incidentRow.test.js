import { createElement } from 'lwc';
import IncidentRow from 'c/incidentRow';

function mount(incident) {
    const element = createElement('c-incident-row', { is: IncidentRow });
    element.incident = incident;
    document.body.appendChild(element);
    return element;
}

const BASE = { caseId: '500000000000001AAA', caseNumber: '00001300', team: 'Network', priority: 'High', minutesRemaining: 125 };

describe('c-incident-row', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('shows case number, team and priority', () => {
        const element = mount(BASE);

        expect(element.shadowRoot.querySelector('.case-number').textContent).toBe('00001300');
        expect(element.shadowRoot.querySelector('.team').textContent).toBe('Network');
        expect(element.shadowRoot.querySelector('.priority').label).toBe('High');
    });

    it.each([
        [125, '2h 05m'],
        [0, '0h 00m'],
        [-30, 'Overdue 0h 30m'],
        [null, 'No SLA']
    ])('formats %s minutes remaining as "%s"', (minutes, expected) => {
        const element = mount({ ...BASE, minutesRemaining: minutes });

        expect(element.shadowRoot.querySelector('.time').textContent).toBe(expected);
    });

    it('highlights an overdue Milestone only', () => {
        const overdue = mount({ ...BASE, minutesRemaining: -1 });
        const onTime = mount({ ...BASE, minutesRemaining: 1 });

        expect(overdue.shadowRoot.querySelector('.time').classList).toContain('slds-text-color_error');
        expect(onTime.shadowRoot.querySelector('.time').classList).not.toContain('slds-text-color_error');
    });

    it('sends an "assign" event with the case id when the button is clicked', () => {
        const element = mount(BASE);
        const handler = jest.fn();
        element.addEventListener('assign', handler);

        element.shadowRoot.querySelector('lightning-button').click();

        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail).toEqual({ caseId: BASE.caseId });
    });
});
