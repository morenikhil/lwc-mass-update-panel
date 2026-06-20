/**
 * MassUpdateController
 * Apex controller for the massUpdatePanel LWC.
 * Handles bulk record fetching, mass field updates with partial-success
 * reporting, and rollback to previously captured original values.
 *
 * Security model: enforces with sharing (FLS checked via stripInaccessible).
 */
public with sharing class MassUpdateController {

    // ─── Public DTOs ─────────────────────────────────────────────────────────

    public class MassUpdateResult {
        @AuraEnabled public Integer    successCount    { get; set; }
        @AuraEnabled public Integer    failureCount    { get; set; }
        @AuraEnabled public List<FailedRecord>    failures         { get; set; }
        @AuraEnabled public List<RollbackRecord>  rollbackSnapshot { get; set; }
        @AuraEnabled public String     message         { get; set; }
    }

    public class FailedRecord {
        @AuraEnabled public Id     recordId     { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
    }

    public class RollbackRecord {
        @AuraEnabled public Id     recordId      { get; set; }
        @AuraEnabled public String originalValue { get; set; }
    }

    // ─── getRecords ───────────────────────────────────────────────────────────

    /**
     * Fetches records for the datatable. Called by the host page / parent LWC.
     *
     * @param sobjectApiName  API name of the SObject (e.g. 'Account')
     * @param fields          Comma-separated list of fields to query
     * @param whereClause     Optional WHERE clause (without the WHERE keyword)
     * @param maxRows         Maximum rows to return (default 200, hard cap 2000)
     */
    @AuraEnabled(cacheable=true)
    public static List<SObject> getRecords(
        String sobjectApiName,
        String fields,
        String whereClause,
        Integer maxRows
    ) {
        validateObjectAccess(sobjectApiName);
        Integer limitVal = (maxRows != null && maxRows > 0 && maxRows <= 2000) ? maxRows : 200;

        String safeFields = sanitizeFields(fields);
        String soql = 'SELECT ' + safeFields + ' FROM ' + String.escapeSingleQuotes(sobjectApiName);

        if (String.isNotBlank(whereClause)) {
            soql += ' WHERE ' + whereClause; // caller must sanitise; document accordingly
        }
        soql += ' LIMIT ' + limitVal;

        List<SObject> raw = Database.query(soql);
        SObjectAccessDecision decision = Security.stripInaccessible(AccessType.READABLE, raw);
        return decision.getRecords();
    }

    // ─── massUpdate ───────────────────────────────────────────────────────────

    /**
     * Bulk-updates a single field across the supplied record IDs.
     * Uses Database.update with allOrNone=false so partial successes are surfaced.
     * Returns a rollback snapshot of original values captured BEFORE the DML.
     *
     * @param sobjectApiName  API name of the SObject
     * @param fieldApiName    API name of the field to update
     * @param newValue        New value as String (cast inside as needed)
     * @param recordIdsJson   JSON-serialised List<Id>
     */
    @AuraEnabled
    public static MassUpdateResult massUpdate(
        String  sobjectApiName,
        String  fieldApiName,
        String  newValue,
        String  recordIdsJson
    ) {
        validateObjectAccess(sobjectApiName);
        validateFieldAccess(sobjectApiName, fieldApiName, AccessType.UPDATABLE);

        List<Id> recordIds = (List<Id>) JSON.deserialize(recordIdsJson, List<Id>.class);
        if (recordIds == null || recordIds.isEmpty()) {
            throw new AuraHandledException('No record IDs supplied.');
        }

        // Capture originals for rollback
        List<RollbackRecord> snapshot = captureOriginals(sobjectApiName, fieldApiName, recordIds);

        // Build update list
        Schema.SObjectType objType    = Schema.getGlobalDescribe().get(sobjectApiName);
        Schema.SObjectField fieldToken = objType.getDescribe().fields.getMap().get(fieldApiName);
        Schema.DisplayType  fieldDT   = fieldToken.getDescribe().getType();

        List<SObject> toUpdate = new List<SObject>();
        for (Id rid : recordIds) {
            SObject rec = objType.newSObject(rid);
            rec.put(fieldApiName, castValue(newValue, fieldDT));
            toUpdate.add(rec);
        }

        Database.SaveResult[] results = Database.update(toUpdate, false);

        // Collate results
        MassUpdateResult outcome  = new MassUpdateResult();
        outcome.failures          = new List<FailedRecord>();
        outcome.rollbackSnapshot  = snapshot;
        outcome.successCount      = 0;
        outcome.failureCount      = 0;

        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                outcome.successCount++;
            } else {
                outcome.failureCount++;
                FailedRecord fr = new FailedRecord();
                fr.recordId     = toUpdate[i].Id;
                fr.errorMessage = results[i].getErrors()[0].getMessage();
                outcome.failures.add(fr);
            }
        }

        outcome.message = outcome.successCount + ' record(s) updated successfully. '
                        + outcome.failureCount  + ' failed.';
        return outcome;
    }

    // ─── rollbackUpdate ───────────────────────────────────────────────────────

    /**
     * Restores original field values from a snapshot produced by massUpdate.
     *
     * @param sobjectApiName     API name of the SObject
     * @param fieldApiName       API name of the field that was updated
     * @param rollbackDataJson   JSON-serialised List<RollbackRecord>
     */
    @AuraEnabled
    public static MassUpdateResult rollbackUpdate(
        String sobjectApiName,
        String fieldApiName,
        String rollbackDataJson
    ) {
        validateObjectAccess(sobjectApiName);
        validateFieldAccess(sobjectApiName, fieldApiName, AccessType.UPDATABLE);

        List<RollbackRecord> rollbackData =
            (List<RollbackRecord>) JSON.deserialize(rollbackDataJson, List<RollbackRecord>.class);

        if (rollbackData == null || rollbackData.isEmpty()) {
            throw new AuraHandledException('No rollback data supplied.');
        }

        Schema.SObjectType  objType    = Schema.getGlobalDescribe().get(sobjectApiName);
        Schema.SObjectField fieldToken = objType.getDescribe().fields.getMap().get(fieldApiName);
        Schema.DisplayType  fieldDT    = fieldToken.getDescribe().getType();

        List<SObject> toUpdate = new List<SObject>();
        for (RollbackRecord rr : rollbackData) {
            SObject rec = objType.newSObject(rr.recordId);
            rec.put(fieldApiName, castValue(rr.originalValue, fieldDT));
            toUpdate.add(rec);
        }

        Database.SaveResult[] results = Database.update(toUpdate, false);

        MassUpdateResult outcome = new MassUpdateResult();
        outcome.failures         = new List<FailedRecord>();
        outcome.successCount     = 0;
        outcome.failureCount     = 0;

        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                outcome.successCount++;
            } else {
                outcome.failureCount++;
                FailedRecord fr = new FailedRecord();
                fr.recordId     = toUpdate[i].Id;
                fr.errorMessage = results[i].getErrors()[0].getMessage();
                outcome.failures.add(fr);
            }
        }

        outcome.message = 'Rollback complete. ' + outcome.successCount
                        + ' record(s) restored. ' + outcome.failureCount + ' failed.';
        return outcome;
    }

    // ─── Private helpers ──────────────────────────────────────────────────────

    private static List<RollbackRecord> captureOriginals(
        String sobjectApiName,
        String fieldApiName,
        List<Id> recordIds
    ) {
        String idList = '(\'' + String.join(new List<String>((List<String>)(List<Object>)recordIds), '\',\'') + '\')';
        String soql   = 'SELECT Id, ' + String.escapeSingleQuotes(fieldApiName)
                      + ' FROM ' + String.escapeSingleQuotes(sobjectApiName)
                      + ' WHERE Id IN ' + idList;

        List<RollbackRecord> snapshot = new List<RollbackRecord>();
        for (SObject rec : Database.query(soql)) {
            RollbackRecord rr = new RollbackRecord();
            rr.recordId       = rec.Id;
            Object val        = rec.get(fieldApiName);
            rr.originalValue  = val != null ? String.valueOf(val) : null;
            snapshot.add(rr);
        }
        return snapshot;
    }

    private static void validateObjectAccess(String sobjectApiName) {
        Schema.SObjectType objType = Schema.getGlobalDescribe().get(sobjectApiName);
        if (objType == null || !objType.getDescribe().isAccessible()) {
            throw new AuraHandledException('Access denied to object: ' + sobjectApiName);
        }
    }

    private static void validateFieldAccess(String sobjectApiName, String fieldApiName, AccessType accessType) {
        Schema.SObjectType objType      = Schema.getGlobalDescribe().get(sobjectApiName);
        Schema.SObjectField fieldToken  = objType?.getDescribe().fields.getMap().get(fieldApiName);
        if (fieldToken == null) {
            throw new AuraHandledException('Field not found: ' + fieldApiName);
        }
        Schema.DescribeFieldResult dfr = fieldToken.getDescribe();
        if (accessType == AccessType.UPDATABLE && !dfr.isUpdateable()) {
            throw new AuraHandledException('Field is not updateable: ' + fieldApiName);
        }
    }

    private static String sanitizeFields(String fields) {
        if (String.isBlank(fields)) return 'Id';
        List<String> safe = new List<String>();
        for (String f : fields.split(',')) {
            safe.add(String.escapeSingleQuotes(f.trim()));
        }
        return String.join(safe, ', ');
    }

    /**
     * Casts a String value to the appropriate Apex/Salesforce type
     * based on the field's DisplayType.
     */
    private static Object castValue(String val, Schema.DisplayType dt) {
        if (val == null || val == 'null') return null;

        switch on dt {
            when BOOLEAN {
                return Boolean.valueOf(val);
            }
            when INTEGER {
                return Integer.valueOf(val);
            }
            when DOUBLE, CURRENCY, PERCENT {
                return Decimal.valueOf(val);
            }
            when DATE {
                return Date.valueOf(val);
            }
            when DATETIME {
                return DateTime.valueOf(val);
            }
            when else {
                return val; // String, Picklist, Reference, etc.
            }
        }
    }
}
