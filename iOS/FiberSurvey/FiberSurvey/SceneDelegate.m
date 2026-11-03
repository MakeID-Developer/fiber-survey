#import "SceneDelegate.h"
#import "ViewController.h"
#import "Controllers/FSCFiberSurveyController.h"
@interface SceneDelegate ()
@property (nonatomic, strong) FSCFiberSurveyController *surveyController;
@end
@implementation SceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    self.surveyController = [FSCFiberSurveyController new];
    ViewController *root = [[ViewController alloc] initWithController:self.surveyController];
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:root];
    [self.window makeKeyAndVisible];
}
- (void)sceneDidBecomeActive:(UIScene *)scene { [self.surveyController sceneBecameActive]; }
- (void)sceneWillResignActive:(UIScene *)scene { [self.surveyController sceneResignedActive]; }
- (void)sceneDidEnterBackground:(UIScene *)scene {
    [self.window.rootViewController dismissViewControllerAnimated:NO completion:nil];
    [self.surveyController sceneEnteredBackground];
}
- (void)sceneDidDisconnect:(UIScene *)scene { [self.surveyController tearDown]; }
@end
