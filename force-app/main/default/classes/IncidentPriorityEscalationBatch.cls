/**
 * Escalonamento de prioridade por sobrecarga de fila.
 *
 * Por fila, conta os incidentes abertos de prioridade Critical e High. Se ultrapassar o limite
 * (Escalation_Threshold__mdt, por fila ou Default), sobe de High para Critical os casos mais antigos,
 * até ao máximo do excesso. Cada caso só é escalado uma vez (Last_Escalated_At__c) para não haver
 * escalonamento em cadeia, e cada subida fica registada num CaseComment interno.
 *
 * A seleção é feita em start() com uma única query (sem SOQL em loops); execute() só atualiza os casos escolhidos.
 * shortcut: o plano lê até 50 000 incidentes abertos Critical/High em start(); acima disso, mudar para agregação por fila.
 */
public with sharing class IncidentPriorityEscalationBatch implements Database.Batchable<SObject>, Database.Stateful {

    public static final Integer SCOPE_SIZE = 200;
    private static final String DEFAULT_KEY = 'Default';
    private static final String QUEUE_PREFIX = '00G';

    // Só para testes: limites por DeveloperName da fila (e 'Default'), em vez do Custom Metadata.
    @TestVisible private static Map<String, Integer> thresholdOverride;

    // Motivo por caso, calculado em start() e usado em execute() (Stateful).
    private Map<Id, String> reasons = new Map<Id, String>();
    private Integer escalated = 0;
    private Integer failed = 0;

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Set<Id> selected = planEscalation();
        return Database.getQueryLocator([
            SELECT Id, Priority, Last_Escalated_At__c
            FROM Case
            WHERE Id IN :selected
            WITH USER_MODE
            ORDER BY CreatedDate ASC
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Case> scope) {
        Datetime now = Datetime.now();
        List<Case> toUpdate = new List<Case>();
        for (Case c : scope) {
            // Revalida: o caso pode ter mudado entre start() e execute().
            if (c.Priority == 'High' && c.Last_Escalated_At__c == null) {
                c.Priority = 'Critical';
                c.Last_Escalated_At__c = now;
                toUpdate.add(c);
            }
        }
        if (toUpdate.isEmpty()) {
            return;
        }

        List<Database.SaveResult> results = Database.update(toUpdate, false, AccessLevel.USER_MODE);
        List<CaseComment> comments = new List<CaseComment>();
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                escalated++;
                comments.add(new CaseComment(
                    ParentId = toUpdate[i].Id,
                    CommentBody = reasons.get(toUpdate[i].Id),
                    IsPublished = false
                ));
            } else {
                failed++;
            }
        }
        Database.insert(comments, false, AccessLevel.USER_MODE);
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('IncidentPriorityEscalationBatch: escalados=' + escalated + ', falhas=' + failed);
    }

    /** Devolve os Ids a escalar e preenche os motivos. */
    private Set<Id> planEscalation() {
        List<Case> open = [
            SELECT Id, OwnerId, Priority, Last_Escalated_At__c
            FROM Case
            WHERE RecordType.DeveloperName = 'Incident_IT'
              AND IsClosed = false
              AND Priority IN ('Critical', 'High')
            WITH USER_MODE
            ORDER BY CreatedDate ASC, Id ASC
            LIMIT 50000
        ];

        Map<Id, List<Case>> byQueue = new Map<Id, List<Case>>();
        for (Case c : open) {
            if (String.valueOf(c.OwnerId).startsWith(QUEUE_PREFIX)) {
                if (!byQueue.containsKey(c.OwnerId)) {
                    byQueue.put(c.OwnerId, new List<Case>());
                }
                byQueue.get(c.OwnerId).add(c);
            }
        }
        if (byQueue.isEmpty()) {
            return new Set<Id>();
        }

        Map<Id, Group> queues = new Map<Id, Group>([
            SELECT Id, Name, DeveloperName FROM Group WHERE Id IN :byQueue.keySet() WITH USER_MODE
        ]);
        Map<String, Integer> thresholds = loadThresholds();

        Set<Id> selected = new Set<Id>();
        for (Id queueId : byQueue.keySet()) {
            Group q = queues.get(queueId);
            if (q == null) {
                continue;
            }
            Integer limitForQueue = thresholds.containsKey(q.DeveloperName) ? thresholds.get(q.DeveloperName) : thresholds.get(DEFAULT_KEY);
            if (limitForQueue == null) {
                continue;
            }
            List<Case> cases = byQueue.get(queueId);
            Integer excess = cases.size() - limitForQueue;
            Integer picked = 0;
            for (Case c : cases) {
                if (picked >= excess) {
                    break;
                }
                // Só High -> Critical, e só se nunca foi escalado.
                if (c.Priority == 'High' && c.Last_Escalated_At__c == null) {
                    selected.add(c.Id);
                    reasons.put(c.Id, buildReason(q.Name, cases.size(), limitForQueue, excess));
                    picked++;
                }
            }
        }
        return selected;
    }

    private static Map<String, Integer> loadThresholds() {
        if (thresholdOverride != null) {
            return thresholdOverride;
        }
        Map<String, Integer> result = new Map<String, Integer>();
        for (Escalation_Threshold__mdt t : Escalation_Threshold__mdt.getAll().values()) {
            result.put(t.DeveloperName, Integer.valueOf(t.Max_Open_Critical_High__c));
        }
        return result;
    }

    private static String buildReason(String queueName, Integer open, Integer maxAllowed, Integer excess) {
        return 'Prioridade subida de High para Critical pelo escalonamento automático: a fila "' + queueName + '" tinha '
            + open + ' incidentes Critical/High abertos (limite ' + maxAllowed + ', excesso ' + excess + '); este está entre os mais antigos. '
            + 'Atenção: mudar a Priority recalcula o prazo do Milestone em curso (de 4 h para 1 h, contado desde o início do SLA); '
            + 'um incidente com mais de 1 h pode ficar logo com o Milestone violado.';
    }
}
