"""Source-level regressions: do not compile, execute SDK methods, or connect hardware."""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[2]
JAVA=ROOT/'app/src/main/java/com/makeid/fibersurveydemo'
class SourceContract(unittest.TestCase):
    def source(self,name):
        path=JAVA/name
        self.assertTrue(path.is_file(), 'Missing implementation: '+name)
        return path.read_text()
    def test_only_one_sdk_owner(self):
        controller=self.source('FiberSurveyController.java')
        self.assertIn('sdk.init(',controller)
        scan=self.source('ui/FiberScanActivity.java')
        self.assertNotIn('XCFiberCheckManager',scan)
        self.assertNotIn('.release()',scan)
        self.assertIn('scanRequest',scan)
    def test_shutdown_requires_ready_and_user_confirmation(self):
        controller=self.source('FiberSurveyController.java')
        self.assertIn('sdk.isReady()',controller)
        self.assertIn('COMMAND_PENDING',controller)
        activity=self.source('MainActivity.java')
        self.assertIn('AlertDialog.Builder',activity)
        self.assertIn('confirmShutdown',activity)
    def test_background_cleanup_and_local_data(self):
        app=self.source('SurveyApplication.java')
        self.assertIn('ActivityLifecycleCallbacks',app)
        self.assertIn('onActivityStarted',app)
        self.assertIn('onActivityStopped',app)
        controller=self.source('FiberSurveyController.java')
        for method in ['setRawJsonListener(null)','setOnPowerChangeListener(null)',
                       'setOnDevicePowerListener(null)','clearDeviceIdFilter()','sdk.stopScan()','sdk.release()']:
            self.assertIn(method,controller)
    def test_upper_log_lower_operations(self):
        root=ET.parse(ROOT/'app/src/main/res/layout/activity_main.xml').getroot()
        ns='{http://schemas.android.com/apk/res/android}'
        ids=[e.get(ns+'id') for e in root]
        self.assertIn('@+id/log_panel',ids)
        self.assertIn('@+id/operation_scroll',ids)
        self.assertLess(ids.index('@+id/log_panel'),ids.index('@+id/operation_scroll'))
    def test_scan_round_and_pending_connection_callbacks_are_guarded(self):
        source=self.source('FiberSurveyController.java')
        self.assertIn('scanRound',source)
        self.assertIn('scanCurrent(request,round)',source)
        self.assertIn('connectionPending()',source)
    def test_pending_scan_result_keeps_its_request_on_recreation(self):
        source=self.source('MainActivity.java')
        self.assertIn('returnedDevice!=null && returnedRequest==scanRequest',source)
    def test_permission_result_defers_until_resumed_and_api21_has_no_location_gate(self):
        helper=self.source('ui/BlePermissionHelper.java')
        self.assertIn('if (!resumed || awaitingResult || pending==null) return;',helper)
        self.assertIn('Build.VERSION.SDK_INT>=23 && Build.VERSION.SDK_INT<31',helper)
        self.assertIn('permission.onResume()',self.source('MainActivity.java'))
        self.assertIn('permission.onResume()',self.source('ui/FiberScanActivity.java'))
    def test_filter_and_bounded_models_exist(self):
        self.source('core/DetectorFilterParser.java')
        self.source('core/BoundedLogStore.java')
        self.source('core/SessionState.java')
    def test_permission_native_api_and_no_auth_ui(self):
        helper=self.source('ui/BlePermissionHelper.java')
        self.assertIn('BLUETOOTH_SCAN',helper)
        self.assertIn('requestPermissions',helper)
        self.assertNotIn('XXPermissions',helper)
        self.assertNotIn('AppSecret',self.source('MainActivity.java'))
if __name__=='__main__':unittest.main()
