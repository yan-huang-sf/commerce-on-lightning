@isTest
public class B2CPricingSampleTest {
    @testSetup static void setup() {
        Account testAccount = new Account(Name='TestAccount');
        insert testAccount;
        WebStore testWebStore = new WebStore(Name='TestWebStore', SupportedLanguages='en_US', DefaultLanguage='en_US');
        insert testWebStore;

        Account account = [SELECT Id FROM Account WHERE Name='TestAccount' LIMIT 1];
        WebStore webStore = [SELECT Id FROM WebStore WHERE Name='TestWebStore' LIMIT 1];
        WebCart cart = new WebCart(Name='Cart', WebStoreId=webStore.Id, AccountId=account.Id);
        insert cart;

        CartDeliveryGroup cartDeliveryGroup = new CartDeliveryGroup(CartId=cart.Id, Name='Default Delivery');
        insert cartDeliveryGroup;

        CartItem cartItem = new CartItem(CartId=cart.Id, Sku='SKU_Test1', SalesPrice=10.00, Quantity=3.0, Type='Product', Name='TestProduct', CartDeliveryGroupId=cartDeliveryGroup.Id);
        insert cartItem;
    }

    @isTest static void testWhenSalesPriceIsCorrectSuccessStatusIsReturned() {
        // Because test methods do not support Web service callouts, we create a mock response based on a static resource.
        // To create the static resource from the Developer Console, select File | New | Static Resource
        StaticResourceCalloutMock mock = new StaticResourceCalloutMock();
        mock.setStaticResource('GetSalesPricesResource');
        mock.setStatusCode(200);
        mock.setHeader('Content-Type', 'application/json;charset=UTF-8');
        Test.startTest();
        // Associate the callout with a mock response.
        Test.setMock(HttpCalloutMock.class, mock);

        // Test: execute the integration for the test cart ID.
        B2CPricingSample apexSample = new B2CPricingSample();
        WebCart webCart = [SELECT Id FROM WebCart WHERE Name = 'Cart' LIMIT 1];
        sfdc_checkout.IntegrationStatus integrationResult = apexSample.startCartProcessAsync(null, webCart.Id);
        System.assertEquals(sfdc_checkout.IntegrationStatus.Status.SUCCESS, integrationResult.status);
        Test.stopTest();
    }

    @isTest static void testWhenExternalServiceCallFailsAFailedStatusIsReturnedAndACartValidationOutputEntryIsCreated() {
        // Because test methods do not support Web service callouts, we create a mock response based on a static resource.
        // To create the static resource from the Developer Console, select File | New | Static Resource
        StaticResourceCalloutMock mock = new StaticResourceCalloutMock();
        mock.setStaticResource('GetSalesPricesResource');
        // The web service call returns an error code.
        mock.setStatusCode(404);
        mock.setHeader('Content-Type', 'application/json;charset=UTF-8');
        Test.startTest();
        // Associate the callout with a mock response.
        Test.setMock(HttpCalloutMock.class, mock);

        // Test: execute the integration for the test cart ID and integration info.
        B2CPricingSample apexSample = new B2CPricingSample();
        sfdc_checkout.IntegrationInfo integInfo = new sfdc_checkout.IntegrationInfo();
        integInfo.jobId = null;
        WebCart webCart = [SELECT Id FROM WebCart WHERE Name = 'Cart' LIMIT 1];
        sfdc_checkout.IntegrationStatus integrationResult = apexSample.startCartProcessAsync(integInfo, webCart.Id);

        // Validate: IntegrationStatus.Status is FAILED
        // and a new CartValidationOutput record with level 'Error' was created.
        System.assertEquals(sfdc_checkout.IntegrationStatus.Status.FAILED, integrationResult.status);
        List<CartValidationOutput> cartValidationOutputs = [SELECT Id FROM CartValidationOutput WHERE Level = 'Error'];
        System.assertEquals(1, cartValidationOutputs.size());
        Test.stopTest();
    }

    @isTest static void testProductsWithNoSkuHasError() {
        Test.startTest();

        WebCart webCart = [SELECT Id FROM WebCart WHERE Name = 'Cart' LIMIT 1];
        List<CartDeliveryGroup> cartDeliveryGroups = [SELECT Id FROM CartDeliveryGroup WHERE CartId = :webCart.Id LIMIT 1];

        // Insert a cart item without a SKU
        CartItem cartItemWithNoSku = new CartItem(
            CartId=webCart.Id,
            Quantity=1.0,
            Type='Product',
            Name='TestProductNoSku',
            CartDeliveryGroupId=cartDeliveryGroups.get(0).Id
        );
        insert cartItemWithNoSku;

        B2CPricingSample apexSample = new B2CPricingSample();
        sfdc_checkout.IntegrationInfo integInfo = new sfdc_checkout.IntegrationInfo();
        integInfo.jobId = null;
        sfdc_checkout.IntegrationStatus integrationResult = apexSample.startCartProcessAsync(integInfo, webCart.Id);

        // Validate: IntegrationStatus.Status is FAILED.
        // and a new CartValidationOutput record with level 'Error' was created.
        System.assertEquals(sfdc_checkout.IntegrationStatus.Status.FAILED, integrationResult.status);
        List<CartValidationOutput> cartValidationOutputs = [SELECT Id, Message FROM CartValidationOutput WHERE Level = 'Error'];
        System.assertEquals(1, cartValidationOutputs.size());

        // Validate: The sample text that a product SKU is missing is returned as the failure output
        System.assertEquals('The SKUs for all products in your cart must be defined.', cartValidationOutputs.get(0).Message);
        Test.stopTest();

        // Remove the invalid cart item
        delete cartItemWithNoSku;
    }
}
