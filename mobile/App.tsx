// Hear Me Coach native app: wraps the web app (same backend, same features) and adds what a web app
// cannot do reliably: receiving shares from TikTok/Instagram/YouTube, push notifications, persistent storage.
import React, { useCallback, useEffect, useRef, useState } from 'react';
import { ActivityIndicator, AppState, BackHandler, Linking, Platform, Pressable, StyleSheet, Text, View } from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { StatusBar } from 'expo-status-bar';
import { WebView as RNWebView, type WebViewMessageEvent } from 'react-native-webview';
import type { WebViewProps } from 'react-native-webview/lib/WebView';

// The package types WebView as a plain function component without a ref; describe the handle we use.
type WebViewHandle = { injectJavaScript: (js: string) => void; goBack: () => void };
const WebView = RNWebView as unknown as React.ComponentType<WebViewProps & { ref?: React.Ref<WebViewHandle> }>;
import * as Notifications from 'expo-notifications';
import * as Device from 'expo-device';
import Constants from 'expo-constants';
import { useShareIntent } from 'expo-share-intent';

const WEB_URL: string = (Constants.expoConfig?.extra as { webAppUrl?: string } | undefined)?.webAppUrl
  ?? 'https://j3sk0.github.io/hear-me-coach/';
const WEB_ORIGIN = new URL(WEB_URL).origin;
const BRAND = '#151d19';

Notifications.setNotificationHandler({
  handleNotification: async () => ({ shouldShowBanner: true, shouldShowList: true, shouldPlaySound: true, shouldSetBadge: false }),
});

// Strings are passed into the page as JSON literals, never concatenated as code.
const call = (fn: string, ...args: unknown[]) =>
  `try { window.hmcNative && window.hmcNative.${fn}(${args.map(a => JSON.stringify(a)).join(',')}); } catch (e) {} true;`;

async function getPushToken(ask: boolean): Promise<string | 'denied' | null> {
  if (!Device.isDevice) return null;
  if (Platform.OS === 'android') {
    await Notifications.setNotificationChannelAsync('default', {
      name: 'Hear Me Coach', importance: Notifications.AndroidImportance.HIGH, lightColor: '#ff5a3c',
    });
  }
  let { status } = await Notifications.getPermissionsAsync();
  if (status !== 'granted' && ask) status = (await Notifications.requestPermissionsAsync()).status;
  if (status !== 'granted') return 'denied';
  const projectId = Constants.expoConfig?.extra?.eas?.projectId ?? Constants.easConfig?.projectId;
  if (!projectId) return null;
  return (await Notifications.getExpoPushTokenAsync({ projectId })).data;
}

function Main() {
  const web = useRef<WebViewHandle>(null);
  const [ready, setReady] = useState(false);       // page loaded and bridge available
  const [failed, setFailed] = useState(false);
  const pending = useRef<string[]>([]);            // scripts waiting for the page
  const canGoBack = useRef(false);
  const { hasShareIntent, shareIntent, resetShareIntent } = useShareIntent({ resetOnBackground: true });
  const lastResponse = Notifications.useLastNotificationResponse();

  const run = useCallback((js: string) => {
    if (ready && web.current) web.current.injectJavaScript(js); else pending.current.push(js);
  }, [ready]);

  useEffect(() => {
    if (!ready || !web.current) return;
    pending.current.splice(0).forEach(js => web.current?.injectJavaScript(js));
  }, [ready]);

  // Shared from another app -> open the share form in the web app
  useEffect(() => {
    if (!hasShareIntent) return;
    const text = shareIntent.webUrl || shareIntent.text || '';
    if (text) run(call('share', text));
    resetShareIntent();
  }, [hasShareIntent, shareIntent, resetShareIntent, run]);

  // Notification tapped -> jump to the tab it belongs to
  const handled = useRef<string | null>(null);
  useEffect(() => {
    if (!lastResponse) return;
    const id = lastResponse.notification.request.identifier;
    if (handled.current === id) return;
    handled.current = id;
    const tab = (lastResponse.notification.request.content.data as { tab?: string } | undefined)?.tab ?? null;
    run(call('open', tab));
  }, [lastResponse, run]);

  const registerPush = useCallback(async (ask: boolean) => {
    try {
      const t = await getPushToken(ask);
      if (t === 'denied') { if (ask) run(call('pushDenied')); return; }
      if (t) run(call('pushToken', t, Platform.OS));
    } catch { /* push is optional; the app works without it */ }
  }, [run]);

  const onMessage = useCallback((e: WebViewMessageEvent) => {
    let msg: { type?: string } = {};
    try { msg = JSON.parse(e.nativeEvent.data); } catch { return; }
    if (msg.type === 'loggedIn') registerPush(true);
    if (msg.type === 'enablePush') registerPush(true);
  }, [registerPush]);

  // Android back button: navigate back inside the page first
  useEffect(() => {
    const sub = BackHandler.addEventListener('hardwareBackPress', () => {
      if (canGoBack.current && web.current) { web.current.goBack(); return true; }
      return false;
    });
    return () => sub.remove();
  }, []);

  // Refresh data when the app comes back to the foreground
  useEffect(() => {
    const sub = AppState.addEventListener('change', s => { if (s === 'active') run('window.dispatchEvent(new Event("visibilitychange")); true;'); });
    return () => sub.remove();
  }, [run]);

  // Videos and other sites open in the real app/browser (TikTok, Instagram, YouTube …)
  const allowInApp = (url: string) => url.startsWith(WEB_ORIGIN) || url.startsWith('about:') || url.startsWith('data:') || url.startsWith('blob:');

  if (failed) {
    return (
      <View style={styles.center}>
        <Text style={styles.title}>Keine Verbindung</Text>
        <Text style={styles.text}>Hear Me Coach braucht Internet. Prüfe dein WLAN oder die mobilen Daten.</Text>
        <Pressable style={styles.btn} onPress={() => { setFailed(false); setReady(false); }}>
          <Text style={styles.btnText}>Erneut versuchen</Text>
        </Pressable>
      </View>
    );
  }

  return (
    <SafeAreaView style={styles.safe} edges={['top', 'left', 'right']}>
      <StatusBar style="light" />
      <WebView
        ref={web}
        source={{ uri: WEB_URL }}
        style={styles.web}
        applicationNameForUserAgent="HearMeCoachApp/1.0"
        originWhitelist={['https://*', 'about:*', 'data:*', 'blob:*']}
        javaScriptEnabled
        domStorageEnabled
        sharedCookiesEnabled
        allowsBackForwardNavigationGestures
        pullToRefreshEnabled
        setSupportMultipleWindows={false}
        mediaPlaybackRequiresUserAction
        startInLoadingState
        renderLoading={() => <View style={styles.center}><ActivityIndicator size="large" color="#ff5a3c" /></View>}
        onMessage={onMessage}
        onLoadEnd={() => setReady(true)}
        onNavigationStateChange={n => { canGoBack.current = n.canGoBack; }}
        onError={() => setFailed(true)}
        onHttpError={e => { if (e.nativeEvent.statusCode >= 500) setFailed(true); }}
        onShouldStartLoadWithRequest={req => {
          if (allowInApp(req.url)) return true;
          Linking.openURL(req.url).catch(() => {});
          return false;
        }}
        onOpenWindow={e => { Linking.openURL(e.nativeEvent.targetUrl).catch(() => {}); }}
      />
    </SafeAreaView>
  );
}

export default function App() {
  return (
    <SafeAreaProvider>
      <Main />
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: BRAND },
  web: { flex: 1, backgroundColor: BRAND },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: 28, backgroundColor: BRAND },
  title: { color: '#fff', fontSize: 26, fontWeight: '700', marginBottom: 10 },
  text: { color: '#cfd8d2', fontSize: 16, textAlign: 'center', marginBottom: 20 },
  btn: { backgroundColor: '#ff5a3c', paddingHorizontal: 22, paddingVertical: 12, borderRadius: 12 },
  btnText: { color: '#fff', fontSize: 17, fontWeight: '700' },
});
