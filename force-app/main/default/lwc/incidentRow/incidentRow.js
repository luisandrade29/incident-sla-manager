import { LightningElement, api } from 'lwc';

export default class IncidentRow extends LightningElement {
    @api incident;

    get isOverdue() {
        return this.incident.minutesRemaining < 0;
    }

    get timeClass() {
        return 'slds-col slds-size_3-of-12 time' + (this.isOverdue ? ' slds-text-color_error' : '');
    }

    get timeLabel() {
        const minutes = this.incident.minutesRemaining;
        if (minutes === null || minutes === undefined) {
            return 'No SLA';
        }
        const abs = Math.abs(minutes);
        const text = `${Math.floor(abs / 60)}h ${String(abs % 60).padStart(2, '0')}m`;
        return this.isOverdue ? `Overdue ${text}` : text;
    }

    // The row only reports the click; the parent owns the Apex call and the refresh.
    handleAssign() {
        this.dispatchEvent(new CustomEvent('assign', { detail: { caseId: this.incident.caseId } }));
    }
}
