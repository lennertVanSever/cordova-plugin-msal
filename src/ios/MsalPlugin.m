#import "MsalPlugin.h"
#import <Cordova/CDVPlugin.h>
#import <MSAL/MSAL.h>

@implementation MsalPlugin

- (void)msalInit:(CDVInvokedUrlCommand *)command
{
    NSDictionary *settings = self.commandDelegate.settings;
    self.tenantId = [settings objectForKey:[@"tenantId" lowercaseString]];
    self.clientId = [settings objectForKey:[@"clientId" lowercaseString]];

    NSError *err = nil;
    NSError *msalError = nil;
    CDVPluginResult *result = nil;
    
    MSALAuthority *defaultAuthority;
    NSMutableArray<MSALAuthority *> *allAuthorities = [NSMutableArray alloc];

    NSString *argument = [command.arguments objectAtIndex:0];
    NSData *json = [argument dataUsingEncoding:NSUTF8StringEncoding];
    id obj = [NSJSONSerialization JSONObjectWithData:json options:0 error:&err];
    if (err)
    {
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"Error parsing options object: %@", err]];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }
    NSDictionary *options = (NSDictionary *)obj;
    NSArray *authorities = [options objectForKey:@"authorities"];
    for (NSDictionary *a in authorities)
    {
        MSALAuthority *authority;
        MSALAudienceType audience = MSALAzureADAndPersonalMicrosoftAccountAudience;
        if ([[a objectForKey:@"audience"] isEqualToString:@"AzureADMyOrg"])
        {
            audience = MSALAzureADMyOrgOnlyAudience;
        }
        else if ([[a objectForKey:@"audience"] isEqualToString:@"AzureADMultipleOrgs"])
        {
            audience = MSALAzureADMultipleOrgsAudience;
        }
        else if ([[a objectForKey:@"audience"] isEqualToString:@"PersonalMicrosoftAccount"])
        {
            audience = MSALPersonalMicrosoftAccountAudience;
        }
        MSALAzureCloudInstance cloudInstance = MSALAzurePublicCloudInstance;
        if (([[a objectForKey:@"cloudInstance"] isEqualToString:@"MSALAzureChinaCloudInstance"]))
        {
            cloudInstance = MSALAzureChinaCloudInstance;
        }
        if (([[a objectForKey:@"cloudInstance"] isEqualToString:@"MSALAzureGermanyCloudInstance"]))
        {
            cloudInstance = MSALAzureGermanyCloudInstance;
        }
        if (([[a objectForKey:@"cloudInstance"] isEqualToString:@"MSALAzureUsGovernmentCloudInstance"]))
        {
            cloudInstance = MSALAzureUsGovernmentCloudInstance;
        }
        if ([(NSString *)[a objectForKey:@"type"] isEqualToString:@"AAD"])
        {
            authority = [[MSALAADAuthority alloc] initWithCloudInstance:MSALAzurePublicCloudInstance audienceType:MSALAzureADAndPersonalMicrosoftAccountAudience rawTenant:self.tenantId error:&err];
        }
        else
        {
            NSURL *authorityUrl = [[NSURL alloc] initWithString:(NSString *)[a objectForKey:@"authorityUrl"]];
            authority = [[MSALB2CAuthority alloc] initWithURL:authorityUrl error:&err];
        }
        [allAuthorities addObject:authority];
        if ([a objectForKey:@"default"] == [NSNumber numberWithBool:YES]) {
            defaultAuthority = authority;
        }
    }
    
    self.config = [[MSALPublicClientApplicationConfig alloc] initWithClientId:[self clientId] redirectUri:[NSString stringWithFormat:@"msauth.%@://auth", [[NSBundle mainBundle] bundleIdentifier]] authority:defaultAuthority];
    [self.config setKnownAuthorities:[[NSArray<MSALAuthority *> alloc] initWithArray:allAuthorities copyItems:YES]];
    [self.config setMultipleCloudsSupported:[options objectForKey:@"multipleCloudsSupported"] == [NSNumber numberWithBool:YES]];
    self.application = [[MSALPublicClientApplication alloc] initWithConfiguration:[self config] error:&msalError];
    self.scopes = [options objectForKey:@"scopes"];
    self.accountMode = [options objectForKey:@"accountMode"];
    if (msalError)
    {
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"Error creating MSAL configuration: %@", msalError]];
    }
    else
    {
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    }
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void)getAccounts:(CDVInvokedUrlCommand *)command
{
    NSMutableArray<NSDictionary *> *accounts = [NSMutableArray<NSDictionary *> alloc];
    for (MSALAccount *account in [[self application] allAccounts:nil])
    {
        NSDictionary *accountObj = [NSDictionary alloc];
        [accountObj setValue:[account identifier] forKey:@"id"];
        [accountObj setValue:[account username] forKey:@"username"];
        [accounts addObject:accountObj];
    }
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:accounts];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void)signInSilent:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult * pluginResult = nil;
    NSError *error = nil;
    NSArray *accounts = [[self application] allAccounts:nil];
    if ([accounts count] == 0)
    {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"No accounts found on device."];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }
    MSALAccount *account = nil;
    if ([self.accountMode isEqualToString:@"SINGLE"])
    {
        account = accounts[0];
    }
    else
    {
        NSError *error = nil;
        NSString *accountId = [command.arguments objectAtIndex:0];
        account = [[self application] accountForIdentifier:accountId error:&error];
        if (error)
        {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            return;
        }
    }
    if (!account)
    {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }
        
    MSALSilentTokenParameters *silentParams = [[MSALSilentTokenParameters alloc] initWithScopes:[self scopes] account:account];
    [[self application] acquireTokenSilentWithParameters:silentParams completionBlock:^(MSALResult *result, NSError *error) {
        if (!error)
        {
            CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:result.accessToken];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
        else
        {
            if ([error.domain isEqual:MSALErrorDomain] && error.code == MSALErrorInteractionRequired)
            {
                CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"No account currently exists"];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            }
                
            // Other errors may require trying again later, or reporting authentication problems to the user
        }
    }];
}

- (void)signInInteractive:(CDVInvokedUrlCommand*)command
{
    MSALWebviewParameters *webParameters = [[MSALWebviewParameters alloc] initWithParentViewController:[self viewController]];

    MSALInteractiveTokenParameters *interactiveParams = [[MSALInteractiveTokenParameters alloc] initWithScopes:[self scopes] webviewParameters:webParameters];
    [[self application] acquireTokenWithParameters:interactiveParams completionBlock:^(MSALResult *result, NSError *error) {
        if (!error)
        {
            CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:result.accessToken];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
        else
        {
            CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    }];
}

- (void)signOut:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
    NSError *error = nil;
    NSArray *accounts = [[self application] allAccounts:nil];
    if ([accounts count] == 0)
    {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }
    MSALAccount *account = nil;
    if ([self.accountMode isEqualToString:@"SINGLE"])
    {
        account = accounts[0];
    }
    else
    {
        NSError *error = nil;
        NSString *accountId = [command.arguments objectAtIndex:0];
        account = [[self application] accountForIdentifier:accountId error:&error];
        if (error)
        {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            return;
        }
    }
    if ([[self application] removeAccount:account error:&error]) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    }
    else
    {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

@end
