import { createElement } from 'lwc';
import IncidentDashboard from 'c/incidentDashboard';
import { refreshApex } from '@salesforce/apex';
import getOpenIncidents from '@salesforce/apex/IncidentDashboardController.getOpenIncidents';
import assignToMe from '@salesforce/apex/IncidentDashboardController.assignToMe';

jest.mock(
    '@salesforce/apex/IncidentDashboardController.getOpenIncidents',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
jest.mock('@salesforce/apex/IncidentDashboardController.assignToMe', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex', () => ({ refreshApex: jest.fn(() => Promise.resolve()) }), { virtual: true });

const INCIDENTS = [
    { caseId: '500A', caseNumber: '00001', team: 'Network', priority: 'High', minutesRemaining: 90 },
    { caseId: '500B', caseNumber: '00002', team: 'Security', priority: 'Low', minutesRemaining: null },
    { caseId: '500C', caseNumber: '00003', team: 'Network', priority: 'Critical', minutesRemaining: -15 }
];

// The jest stub of lightning/platformShowToastEvent does not export this name.
const SHOW_TOAST = 'lightning__showtoast';
// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function mount() {
    const element = createElement('c-incident-dashboard', { is: IncidentDashboard });
    document.body.appendChild(element);
    return element;
}

const rowsOf = (element) => [...element.shadowRoot.querySelectorAll('c-incident-row')];

describe('c-incident-dashboard', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('lists the incidents, most urgent first and without a deadline last', async () => {
        const element = mount();
        getOpenIncidents.emit(INCIDENTS);
        await flushPromises();

        expect(rowsOf(element).map((r) => r.incident.caseNumber)).toEqual(['00003', '00001', '00002']);
    });

    it('filters by team', async () => {
        const element = mount();
        getOpenIncidents.emit(INCIDENTS);
        await flushPromises();

        element.shadowRoot.querySelector('lightning-combobox').dispatchEvent(new CustomEvent('change', { detail: { value: 'Network' } }));
        await flushPromises();

        expect(rowsOf(element).map((r) => r.incident.team)).toEqual(['Network', 'Network']);
    });

    it('shows an empty state when nothing matches the filter', async () => {
        const element = mount();
        getOpenIncidents.emit([]);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.empty')).not.toBeNull();
        expect(rowsOf(element)).toHaveLength(0);
    });

    it('shows the error message when the wire fails', async () => {
        const element = mount();
        // The adapter wraps this argument as error.body, like the real platform does.
        getOpenIncidents.error({ message: 'No access' });
        await flushPromises();

        expect(element.shadowRoot.querySelector('.error').textContent).toBe('No access');
        expect(element.shadowRoot.querySelector('.empty')).toBeNull();
    });

    it('assigns on the row event, confirms with a toast and refreshes the list', async () => {
        assignToMe.mockResolvedValue();
        const element = mount();
        getOpenIncidents.emit(INCIDENTS);
        await flushPromises();
        const toast = jest.fn();
        element.addEventListener(SHOW_TOAST, toast);

        rowsOf(element)[0].dispatchEvent(new CustomEvent('assign', { detail: { caseId: '500C' } }));
        await flushPromises();

        expect(assignToMe).toHaveBeenCalledWith({ caseId: '500C' });
        expect(refreshApex).toHaveBeenCalledTimes(1);
        expect(toast.mock.calls[0][0].detail.variant).toBe('success');
    });

    it('shows an error toast and does not refresh when the assignment fails', async () => {
        assignToMe.mockRejectedValue({ body: { message: 'This incident is no longer open.' } });
        const element = mount();
        getOpenIncidents.emit(INCIDENTS);
        await flushPromises();
        const toast = jest.fn();
        element.addEventListener(SHOW_TOAST, toast);

        rowsOf(element)[0].dispatchEvent(new CustomEvent('assign', { detail: { caseId: '500C' } }));
        await flushPromises();

        expect(refreshApex).not.toHaveBeenCalled();
        expect(toast.mock.calls[0][0].detail.variant).toBe('error');
        expect(toast.mock.calls[0][0].detail.message).toBe('This incident is no longer open.');
    });
});
