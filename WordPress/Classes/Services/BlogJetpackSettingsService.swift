import Foundation
import CocoaLumberjack
import WordPressKit

struct BlogJetpackSettingsService {

    fileprivate let context: NSManagedObjectContext

    init(managedObjectContext context: NSManagedObjectContext) {
        self.context = context
    }

    /// Sync ALL the Jetpack settings for a blog
    ///
    func syncJetpackSettingsForBlog(_ blog: Blog, success: @escaping () -> Void, failure: @escaping (Error?) -> Void) {
        guard blog.supports(.jetpackSettings) else {
            success()
            return
        }
        guard let remote = BlogJetpackSettingsServiceRemote(wordPressComRestApi: blog.wordPressComRestApi()),
            let blogDotComId = blog.dotComID as? Int,
            let blogSettings = blog.settings else {
                success()
                return
        }

        var fetchError: Error? = nil
        var remoteJetpackSettings: RemoteBlogJetpackSettings? = nil
        var remoteJetpackMonitorSettings: RemoteBlogJetpackMonitorSettings? = nil

        // Create a dispatch group to wait for both calls.
        let syncGroup = DispatchGroup()

        syncGroup.enter()
        remote.getJetpackSettingsForSite(blogDotComId,
                                         success: { (remoteSettings) in
                                             remoteJetpackSettings = remoteSettings
                                             syncGroup.leave()
                                         },
                                         failure: { (error) in
                                             fetchError = error
                                             syncGroup.leave()
                                         })

        syncGroup.enter()
        remote.getJetpackMonitorSettingsForSite(blogDotComId,
                                                success: { (remoteMonitorSettings) in
                                                    remoteJetpackMonitorSettings = remoteMonitorSettings
                                                    syncGroup.leave()
                                                },
                                                failure: { (error) in
                                                    fetchError = error
                                                    syncGroup.leave()
                                                })

        syncGroup.notify(queue: DispatchQueue.main, execute: {
            guard let remoteJetpackSettings = remoteJetpackSettings,
                let remoteJetpackMonitorSettings = remoteJetpackMonitorSettings else {
                    failure(fetchError)
                    return
            }
            self.updateJetpackSettings(blogSettings, remoteSettings: remoteJetpackSettings)
            self.updateJetpackMonitorSettings(blogSettings, remoteSettings: remoteJetpackMonitorSettings)
            do {
                try self.context.save()
                success()
            } catch let error as NSError {
                failure(error)
            }
        })
    }

    // Jetpack settings have to be updated one by one because the API does not allow us to do it in any other way.

    func updateJetpackMonitorEnabledForBlog(_ blog: Blog, value: Bool, success: @escaping () -> Void, failure: @escaping (Error?) -> Void) {
        updateJetpackSettingForBlog(blog,
                                    key: BlogJetpackSettingsServiceRemote.Keys.monitorEnabled,
                                    value: value as AnyObject,
                                    success: success,
                                    failure: failure)
    }

    func updateBlockMaliciousLoginAttemptsForBlog(_ blog: Blog, value: Bool, success: @escaping () -> Void, failure: @escaping (Error?) -> Void) {
        updateJetpackSettingForBlog(blog,
                                    key: BlogJetpackSettingsServiceRemote.Keys.blockMaliciousLoginAttempts,
                                    value: value as AnyObject,
                                    success: success,
                                    failure: failure)
    }

    func updateWhiteListedIPAddressesForBlog(_ blog: Blog, value: Set<String>, success: @escaping () -> Void, failure: @escaping (Error?) -> Void) {
        let joinedIPs = value.joined(separator: ", ")
        updateJetpackSettingForBlog(blog,
                                    key: BlogJetpackSettingsServiceRemote.Keys.whiteListedIPAddresses,
                                    value: joinedIPs as AnyObject,
                                    success: success,
                                    failure: failure)
    }

    func updateSSOEnabledForBlog(_ blog: Blog, value: Bool, success: @escaping () -> Void, failure: @escaping (Error?) -> Void) {
        updateJetpackSettingForBlog(blog,
                                    key: BlogJetpackSettingsServiceRemote.Keys.ssoEnabled,
                                    value: value as AnyObject,
                                    success: success,
                                    failure: failure)
    }

    func updateSSOMatchAccountsByEmailForBlog(_ blog: Blog, value: Bool, success: @escaping () -> Void, failure: @escaping (Error?) -> Void) {
        updateJetpackSettingForBlog(blog,
                                    key: BlogJetpackSettingsServiceRemote.Keys.ssoMatchAccountsByEmail,
                                    value: value as AnyObject,
                                    success: success,
                                    failure: failure)
    }

    func updateSSORequireTwoStepAuthenticationForBlog(_ blog: Blog, value: Bool, success: @escaping () -> Void, failure: @escaping (Error?) -> Void) {
        updateJetpackSettingForBlog(blog,
                                    key: BlogJetpackSettingsServiceRemote.Keys.ssoRequireTwoStepAuthentication,
                                    value: value as AnyObject,
                                    success: success,
                                    failure: failure)
    }

    func updateJetpackMonitorSettinsForBlog(_ blog: Blog, success: @escaping () -> Void, failure: @escaping (Error?) -> Void) {
        guard let remote = BlogJetpackSettingsServiceRemote(wordPressComRestApi: blog.wordPressComRestApi()),
            let blogDotComId = blog.dotComID as? Int,
            let blogSettings = blog.settings else {
                failure(nil)
                return
        }

        remote.updateJetpackMonitorSettingsForSite(blogDotComId,
                                                   settings: self.jetpackMonitorsSettingsRemote(blogSettings),
                                                   success: {
                                                       do {
                                                           try self.context.save()
                                                           success()
                                                       } catch let error as NSError {
                                                           failure(error)
                                                       }
                                                   },
                                                   failure: { (error) in
                                                       failure(error)
                                                   })
    }
}

private extension BlogJetpackSettingsService {

    func updateJetpackSettingForBlog(_ blog: Blog, key: String, value: AnyObject, success: @escaping () -> Void, failure: @escaping (Error?) -> Void) {
        guard let remote = BlogJetpackSettingsServiceRemote(wordPressComRestApi: blog.wordPressComRestApi()),
            let blogDotComId = blog.dotComID as? Int else {
                failure(nil)
                return
        }

        remote.updateJetpackSetting(blogDotComId,
                                    key: key,
                                    value: value,
                                    success: {
                                        do {
                                            try self.context.save()
                                            success()
                                        } catch let error as NSError {
                                            failure(error)
                                        }
                                    },
                                    failure: { (error) in
                                        failure(error)
                                    })
    }

    func updateJetpackSettings(_ settings: BlogSettings, remoteSettings: RemoteBlogJetpackSettings) {
        settings.jetpackMonitorEnabled = remoteSettings.monitorEnabled
        settings.jetpackBlockMaliciousLoginAttempts = remoteSettings.blockMaliciousLoginAttempts
        settings.jetpackLoginWhiteListedIPAddresses = remoteSettings.loginWhiteListedIPAddresses
        settings.jetpackSSOEnabled = remoteSettings.ssoEnabled
        settings.jetpackSSOMatchAccountsByEmail = remoteSettings.ssoMatchAccountsByEmail
        settings.jetpackSSORequireTwoStepAuthentication = remoteSettings.ssoRequireTwoStepAuthentication
    }

    func updateJetpackMonitorSettings(_ settings: BlogSettings, remoteSettings: RemoteBlogJetpackMonitorSettings) {
        settings.jetpackMonitorEmailNotifications = remoteSettings.monitorEmailNotifications
        settings.jetpackMonitorPushNotifications = remoteSettings.monitorPushNotifications
    }

    func jetpackMonitorsSettingsRemote(_ settings: BlogSettings) -> RemoteBlogJetpackMonitorSettings {
        return RemoteBlogJetpackMonitorSettings(monitorEmailNotifications: settings.jetpackMonitorEmailNotifications,
                                                monitorPushNotifications: settings.jetpackMonitorPushNotifications)
    }

}
