import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getOpenIncidents from '@salesforce/apex/IncidentDashboardController.getOpenIncidents';
import assignToMe from '@salesforce/apex/IncidentDashboardController.assignToMe';

const ALL = 'All';
const TEAM_OPTIONS = [
    { label: 'All teams', value: ALL },
    { label: 'Infrastructure', value: 'Infrastructure' },
    { label: 'Network', value: 'Network' },
    { label: 'Security', value: 'Security' }
];
// Incidents without a Milestone have no deadline, so they go last.
const NO_DEADLINE = Number.MAX_SAFE_INTEGER;

function messageOf(error) {
    return (error && error.body && error.body.message) || 'Unexpected error';
}

export default class IncidentDashboard extends LightningElement {
    teamOptions = TEAM_OPTIONS;
    selectedTeam = ALL;
    incidents = [];
    errorMessage;
    wiredResult;

    @wire(getOpenIncidents)
    wiredIncidents(result) {
        this.wiredResult = result;
        if (result.data) {
            this.incidents = result.data;
            this.errorMessage = undefined;
        } else if (result.error) {
            this.incidents = [];
            this.errorMessage = messageOf(result.error);
        }
    }

    // Filtering and sorting stay client-side: the controller already caps the list at 200 rows.
    get visibleIncidents() {
        return this.incidents
            .filter((i) => this.selectedTeam === ALL || i.team === this.selectedTeam)
            .sort((a, b) => (a.minutesRemaining ?? NO_DEADLINE) - (b.minutesRemaining ?? NO_DEADLINE));
    }

    get isEmpty() {
        return !this.errorMessage && this.visibleIncidents.length === 0;
    }

    handleTeamChange(event) {
        this.selectedTeam = event.detail.value;
    }

    async handleAssign(event) {
        try {
            await assignToMe({ caseId: event.detail.caseId });
            this.toast('Assigned', 'The incident is now yours.', 'success');
            // The wire result is cached, so it must be refreshed to show the change.
            await refreshApex(this.wiredResult);
        } catch (error) {
            this.toast('Could not assign the incident', messageOf(error), 'error');
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
