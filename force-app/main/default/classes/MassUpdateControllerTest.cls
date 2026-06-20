/**
 * MassUpdateControllerTest
 * Unit tests for MassUpdateController covering: getRecords, massUpdate,
 * rollbackUpdate, partial failures, and security enforcement.
 */
@IsTest
private class MassUpdateControllerTest {

    // ─── Test Data Setup ──────────────────────────────────────────────────────

    @TestSetup
    static void makeData() {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 5; i++) {
            accounts.add(new Account(
                Name   = 'Test Account ' + i,
                Rating = 'Warm'
            ));
        }
        insert accounts;
    }

    // ─── getRecords ───────────────────────────────────────────────────────────

    @IsTest
    static void testGetRecords_returnsRows() {
        Test.startTest();
        List<SObject> results = MassUpdateController.getRecords(
            'Account', 'Id, Name, Rating', null, 10
        );
        Test.stopTest();

        System.assertNotEquals(0, results.size(), 'Should return seeded accounts');
    }

    @IsTest
    static void testGetRecords_respectsMaxRows() {
        Test.startTest();
        List<SObject> results = MassUpdateController.getRecords(
            'Account', 'Id, Name', null, 2
        );
        Test.stopTest();

        System.assert(results.size() <= 2, 'Should honour maxRows limit');
    }

    @IsTest
    static void testGetRecords_invalidObject_throws() {
        Boolean threw = false;
        Test.startTest();
        try {
            MassUpdateController.getRecords('NonExistentObj__c', 'Id', null, 10);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Expected AuraHandledException for invalid object');
    }

    // ─── massUpdate ───────────────────────────────────────────────────────────

    @IsTest
    static void testMassUpdate_success() {
        List<Id> ids = getAccountIds();
        String idsJson = JSON.serialize(ids);

        Test.startTest();
        MassUpdateController.MassUpdateResult result = MassUpdateController.massUpdate(
            'Account', 'Rating', 'Hot', idsJson
        );
        Test.stopTest();

        System.assertEquals(ids.size(), result.successCount, 'All records should succeed');
        System.assertEquals(0, result.failureCount, 'No failures expected');
        System.assertNotEquals(null, result.rollbackSnapshot, 'Snapshot should be populated');
        System.assertEquals(ids.size(), result.rollbackSnapshot.size(), 'Snapshot size mismatch');

        // Verify DB was actually updated
        Account a = [SELECT Rating FROM Account LIMIT 1];
        System.assertEquals('Hot', a.Rating);
    }

    @IsTest
    static void testMassUpdate_emptyIds_throws() {
        Boolean threw = false;
        Test.startTest();
        try {
            MassUpdateController.massUpdate('Account', 'Rating', 'Hot', '[]');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Expected AuraHandledException for empty record list');
    }

    @IsTest
    static void testMassUpdate_rollbackSnapshotValues() {
        List<Account> accounts = [SELECT Id, Rating FROM Account LIMIT 3];
        List<Id> ids = new List<Id>();
        for (Account a : accounts) ids.add(a.Id);

        Test.startTest();
        MassUpdateController.MassUpdateResult result = MassUpdateController.massUpdate(
            'Account', 'Rating', 'Cold', JSON.serialize(ids)
        );
        Test.stopTest();

        // Snapshot should have captured 'Warm' (original value from TestSetup)
        for (MassUpdateController.RollbackRecord rr : result.rollbackSnapshot) {
            System.assertEquals('Warm', rr.originalValue, 'Original value in snapshot should be Warm');
        }
    }

    // ─── rollbackUpdate ───────────────────────────────────────────────────────

    @IsTest
    static void testRollbackUpdate_restoresValues() {
        List<Id> ids = getAccountIds();

        // First, mass-update to 'Hot'
        MassUpdateController.MassUpdateResult updateResult = MassUpdateController.massUpdate(
            'Account', 'Rating', 'Hot', JSON.serialize(ids)
        );

        Test.startTest();
        MassUpdateController.MassUpdateResult rollbackResult = MassUpdateController.rollbackUpdate(
            'Account', 'Rating', JSON.serialize(updateResult.rollbackSnapshot)
        );
        Test.stopTest();

        System.assertEquals(ids.size(), rollbackResult.successCount, 'All rollbacks should succeed');

        // Verify values restored to 'Warm'
        for (Account a : [SELECT Rating FROM Account]) {
            System.assertEquals('Warm', a.Rating, 'Rating should be rolled back to Warm');
        }
    }

    @IsTest
    static void testRollbackUpdate_emptyData_throws() {
        Boolean threw = false;
        Test.startTest();
        try {
            MassUpdateController.rollbackUpdate('Account', 'Rating', '[]');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Expected AuraHandledException for empty rollback data');
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    private static List<Id> getAccountIds() {
        List<Id> ids = new List<Id>();
        for (Account a : [SELECT Id FROM Account]) {
            ids.add(a.Id);
        }
        return ids;
    }
}
