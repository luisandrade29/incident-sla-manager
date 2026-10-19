@IsTest
private class IncidentPriorityEscalationBatchTest {

    @TestSetup
    static void setup() {
        IncidentTestUtil.createManager();
    }

    // Subject and Description on purpose: they prove the Case Classifier guard skips the Incident_IT record type.
    private static List<Case> insertCases(Integer count, String type, String priority) {
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < count; i++) {
            cases.add(new Case(
                Subject = 'Test incident ' + type + ' ' + i,
                Description = 'Test description',
                Type = type,
                Priority = priority
            ));
        }
        System.runAs(IncidentTestUtil.getManager()) {
            insert cases;
        }
        return cases;
    }

    private static void runBatch() {
        Test.startTest();
        System.runAs(IncidentTestUtil.getManager()) {
            Database.executeBatch(new IncidentPriorityEscalationBatch(), IncidentPriorityEscalationBatch.SCOPE_SIZE);
        }
        Test.stopTest();
    }

    // Queries run as the manager: Last_Escalated_At__c is only readable with the permission set.
    private static Integer countByPriority(String type, String priority) {
        Integer n;
        System.runAs(IncidentTestUtil.getManager()) {
            n = [SELECT COUNT() FROM Case WHERE Type = :type AND Priority = :priority];
        }
        return n;
    }

    private static Integer countEscalated() {
        Integer n;
        System.runAs(IncidentTestUtil.getManager()) {
            n = [SELECT COUNT() FROM Case WHERE Last_Escalated_At__c != null];
        }
        return n;
    }

    private static List<CaseComment> comments() {
        List<CaseComment> result;
        System.runAs(IncidentTestUtil.getManager()) {
            result = [SELECT CommentBody, IsPublished FROM CaseComment];
        }
        return result;
    }

    private static void assertNoClassifierJobs() {
        System.assertEquals(0, [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'CaseClassifierQueueable'],
            'The batch and the incidents must not create Case Classifier jobs');
    }

    @IsTest
    static void escalatesOnlyTheExcessAmong200Cases() {
        insertCases(200, 'Infrastructure', 'High');
        IncidentPriorityEscalationBatch.thresholdOverride = new Map<String, Integer>{ 'Default' => 999, 'Infrastructure_Queue' => 150 };

        runBatch();

        System.assertEquals(50, countByPriority('Infrastructure', 'Critical'), 'Only the excess (200 - 150) is raised');
        System.assertEquals(150, countByPriority('Infrastructure', 'High'));
        System.assertEquals(50, countEscalated());

        List<CaseComment> comments = comments();
        System.assertEquals(50, comments.size(), 'One comment per escalated case');
        for (CaseComment cc : comments) {
            System.assertEquals(false, cc.IsPublished, 'The comment must be internal');
            System.assert(cc.CommentBody.contains('Infrastructure Queue') && cc.CommentBody.contains('Milestone'), cc.CommentBody);
        }
        System.assertEquals(1, [SELECT JobItemsProcessed FROM AsyncApexJob WHERE ApexClass.Name = 'IncidentPriorityEscalationBatch' AND JobType = 'BatchApex' LIMIT 1].JobItemsProcessed,
            '200 cases fit in a single scope');
        assertNoClassifierJobs();
    }

    @IsTest
    static void alreadyEscalatedCasesAreIgnored() {
        List<Case> cases = insertCases(4, 'Infrastructure', 'High');
        for (Integer i = 0; i < 2; i++) {
            cases[i].Last_Escalated_At__c = Datetime.now().addDays(-1);
        }
        System.runAs(IncidentTestUtil.getManager()) {
            update cases;
        }
        IncidentPriorityEscalationBatch.thresholdOverride = new Map<String, Integer>{ 'Default' => 2 };

        runBatch();

        System.assertEquals(2, countByPriority('Infrastructure', 'Critical'), 'Only the two not yet escalated are raised');
        System.assertEquals(2, comments().size());
        assertNoClassifierJobs();
    }

    @IsTest
    static void doesNotChainOnASecondRunWhenEveryCaseWasAlreadyEscalated() {
        // State after a first run: the excess remains but nobody is eligible any more.
        List<Case> cases = insertCases(4, 'Infrastructure', 'High');
        for (Case c : cases) {
            c.Last_Escalated_At__c = Datetime.now().addHours(-1);
        }
        System.runAs(IncidentTestUtil.getManager()) {
            update cases;
        }
        IncidentPriorityEscalationBatch.thresholdOverride = new Map<String, Integer>{ 'Default' => 1 };

        runBatch();

        System.assertEquals(4, countByPriority('Infrastructure', 'High'), 'No case is escalated again');
        System.assertEquals(0, comments().size());
    }

    @IsTest
    static void onlyHighBecomesCriticalAndLimitIsPerQueue() {
        insertCases(2, 'Infrastructure', 'Critical');
        insertCases(3, 'Infrastructure', 'High');
        insertCases(2, 'Infrastructure', 'Normal');
        insertCases(3, 'Network', 'High');
        IncidentPriorityEscalationBatch.thresholdOverride = new Map<String, Integer>{ 'Default' => 5, 'Infrastructure_Queue' => 3 };

        runBatch();

        // Infrastructure: 5 Critical/High, limit 3, excess 2: two High rise; Normal and Critical stay.
        System.assertEquals(4, countByPriority('Infrastructure', 'Critical'));
        System.assertEquals(1, countByPriority('Infrastructure', 'High'));
        System.assertEquals(2, countByPriority('Infrastructure', 'Normal'));
        // Network: 3 is under the Default limit (5), nothing changes.
        System.assertEquals(3, countByPriority('Network', 'High'));
    }

    @IsTest
    static void doesNothingWhenUnderThreshold() {
        insertCases(3, 'Security', 'High');
        IncidentPriorityEscalationBatch.thresholdOverride = new Map<String, Integer>{ 'Default' => 10 };
        runBatch();
        System.assertEquals(3, countByPriority('Security', 'High'));
        System.assertEquals(0, comments().size());
    }

    @IsTest
    static void usesCustomMetadataDefaultWhenNoOverride() {
        // No override: reads the Default Escalation_Threshold__mdt record (10).
        Integer limitInMetadata = Integer.valueOf(Escalation_Threshold__mdt.getInstance('Default').Max_Open_Critical_High__c);
        insertCases(limitInMetadata + 2, 'Network', 'High');

        runBatch();

        System.assertEquals(2, countByPriority('Network', 'Critical'), 'Excess of 2 over the Custom Metadata limit');
    }

    @IsTest
    static void schedulerRegistersJobAndRunsBatch() {
        System.runAs(IncidentTestUtil.getManager()) {
            Test.startTest();
            Id cronId = IncidentPriorityEscalationScheduler.schedule(IncidentPriorityEscalationScheduler.CRON_HOURLY);
            System.assertEquals(IncidentPriorityEscalationScheduler.JOB_NAME, [SELECT CronJobDetail.Name FROM CronTrigger WHERE Id = :cronId].CronJobDetail.Name);

            // The schedule only fires next hour, so call execute() directly to prove it launches the batch.
            new IncidentPriorityEscalationScheduler().execute(null);
            Test.stopTest();
        }
        System.assert([SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'IncidentPriorityEscalationBatch' AND JobType = 'BatchApex'] >= 1, 'The scheduler must launch the batch');
    }
}
