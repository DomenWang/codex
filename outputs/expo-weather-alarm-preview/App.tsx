import { StatusBar } from 'expo-status-bar';
import { useEffect, useRef, useState } from 'react';
import {
  Animated,
  Pressable,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';

const moodColors = {
  ink: '#102033',
  muted: '#667085',
  teal: '#0F766E',
  blue: '#1D4ED8',
  amber: '#D97706',
  panel: 'rgba(255,255,255,0.78)',
};

export default function App() {
  const rain = useRef(new Animated.Value(0)).current;
  const [isLogin, setIsLogin] = useState(false);
  const [mode, setMode] = useState<'login' | 'register'>('login');
  const [routeSaved, setRouteSaved] = useState(false);

  useEffect(() => {
    Animated.loop(
      Animated.sequence([
        Animated.timing(rain, { toValue: 1, duration: 1900, useNativeDriver: true }),
        Animated.timing(rain, { toValue: 0, duration: 900, useNativeDriver: true }),
      ]),
    ).start();
  }, [rain]);

  if (isLogin) {
    return (
      <SafeAreaView style={styles.root}>
        <StatusBar style="dark" />
        <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
          <View style={styles.authHero}>
            <Text style={styles.eyebrow}>天气闹钟账号</Text>
            <Text style={styles.authTitle}>把早晨交给一个可靠的地方</Text>
            <Text style={styles.authCopy}>同步订阅状态、通勤路线和提醒配置。令牌会保存在 iOS Keychain。</Text>
          </View>

          <View style={styles.formCard}>
            <Text style={styles.formTitle}>{mode === 'login' ? '登录' : '创建账号'}</Text>
            <TextInput style={styles.input} placeholder="邮箱" autoCapitalize="none" keyboardType="email-address" />
            <TextInput style={styles.input} placeholder="密码，至少 12 位" secureTextEntry />
            {mode === 'register' ? <TextInput style={styles.input} placeholder="昵称，可以稍后再填" /> : null}
            <Pressable style={styles.primaryButton}>
              <Text style={styles.primaryButtonText}>{mode === 'login' ? '登录' : '创建账号'}</Text>
            </Pressable>
            <Pressable onPress={() => setMode(mode === 'login' ? 'register' : 'login')}>
              <Text style={styles.linkText}>{mode === 'login' ? '没有账号，注册' : '已有账号，去登录'}</Text>
            </Pressable>
            <Text style={styles.note}>Expo 预览不提交账号密码；正式 App 会调用 HTTPS 登录接口。</Text>
          </View>
        </ScrollView>
      </SafeAreaView>
    );
  }

  const rainTranslate = rain.interpolate({ inputRange: [0, 1], outputRange: [-8, 10] });

  return (
    <SafeAreaView style={styles.root}>
      <StatusBar style="dark" />
      <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
        <View style={styles.nav}>
          <Text style={styles.title}>天气闹钟</Text>
          <Pressable style={styles.pill} onPress={() => setIsLogin(true)}>
            <Text style={styles.pillText}>登录</Text>
          </Pressable>
        </View>

        <View style={styles.hero}>
          <View style={styles.skyBand} />
          <View style={styles.sun} />
          <Animated.View style={[styles.rainLayer, { transform: [{ translateY: rainTranslate }] }]}>
            <View style={[styles.rainLine, { left: 42 }]} />
            <View style={[styles.rainLine, { left: 78, height: 38 }]} />
            <View style={[styles.rainLine, { left: 116 }]} />
            <View style={[styles.rainLine, { left: 264, height: 42 }]} />
            <View style={[styles.rainLine, { left: 306 }]} />
          </Animated.View>
          <Text style={styles.eyebrow}>明天早晨 · 小雨通勤</Text>
          <Text style={styles.heroTitle}>让雨天慢下来</Text>
          <Text style={styles.heroCopy}>我会在 06:23 轻轻叫醒你，把雨势和驾车通勤都算进去。</Text>

          <View style={styles.metricRow}>
            <Metric title="建议提前" value="57 分" />
            <Metric title="通勤缓冲" value="17 分" />
            <Metric title="天气" value="小雨" />
          </View>

          <View style={styles.moodStatus}>
            <View>
              <Text style={styles.moodLabel}>安心模式</Text>
              <Text style={styles.moodText}>雨和路都算进去了，明早不用临时赶时间。</Text>
            </View>
            <View style={styles.steadyBadge}>
              <Text style={styles.steadyText}>稳</Text>
            </View>
          </View>
        </View>

        <View style={styles.scriptRow}>
          <Script time="06:23" title="轻叫醒" copy="先把早晨放慢" color={moodColors.teal} />
          <Script time="07:08" title="出门窗口" copy="避开雨势最急" color={moodColors.blue} />
          <Script time="07:50" title="预计到达" copy="给路况留余地" color={moodColors.amber} />
        </View>

        <View style={styles.card}>
          <Text style={styles.sectionTitle}>明日天气</Text>
          <Text style={styles.subtle}>小雨，降水概率 68%</Text>
          <View style={styles.weatherRow}>
            <WeatherHour time="06:00" icon="☁" chance="42%" level={0.42} />
            <WeatherHour time="07:00" icon="雨" chance="68%" level={0.68} />
            <WeatherHour time="08:00" icon="雨" chance="71%" level={0.71} />
            <WeatherHour time="09:00" icon="伞" chance="55%" level={0.55} />
          </View>
        </View>

        <View style={styles.card}>
          <Text style={styles.sectionTitle}>建议闹钟时间</Text>
          <Text style={styles.alarmTime}>06:23</Text>
          <Text style={styles.subtle}>天气缓冲 40 分钟，驾车通勤再预留 17 分钟。</Text>
        </View>

        <View style={styles.card}>
          <Text style={styles.sectionTitle}>通勤路线</Text>
          <View style={styles.map}>
            <View style={styles.mapRoadOne} />
            <View style={styles.mapRoadTwo} />
            <View style={styles.routeLine} />
            <View style={[styles.pin, styles.pinStart]} />
            <View style={[styles.pin, styles.pinEnd]} />
          </View>
          <Text style={styles.subtle}>驾车：望京SOHO → 中关村，基础约 42 分钟。</Text>
          <Pressable style={styles.primaryButton} onPress={() => setRouteSaved(!routeSaved)}>
            <Text style={styles.primaryButtonText}>{routeSaved ? '编辑路线' : '保存路线'}</Text>
          </Pressable>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

function Metric({ title, value }: { title: string; value: string }) {
  return (
    <View style={styles.metric}>
      <Text style={styles.metricTitle}>{title}</Text>
      <Text style={styles.metricValue}>{value}</Text>
    </View>
  );
}

function Script({ time, title, copy, color }: { time: string; title: string; copy: string; color: string }) {
  return (
    <View style={styles.scriptCard}>
      <View style={[styles.scriptRail, { backgroundColor: color }]} />
      <Text style={styles.scriptTime}>{time}</Text>
      <Text style={styles.scriptTitle}>{title}</Text>
      <Text style={styles.scriptCopy}>{copy}</Text>
    </View>
  );
}

function WeatherHour({ time, icon, chance, level }: { time: string; icon: string; chance: string; level: number }) {
  return (
    <View style={styles.weatherHour}>
      <View style={[styles.weatherFill, { height: `${level * 100}%` }]} />
      <Text style={styles.weatherTime}>{time}</Text>
      <Text style={styles.weatherIcon}>{icon}</Text>
      <Text style={styles.weatherChance}>{chance}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: '#EAF1F6',
  },
  content: {
    padding: 18,
    paddingBottom: 36,
  },
  nav: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 14,
  },
  title: {
    color: moodColors.ink,
    fontSize: 32,
    fontWeight: '900',
  },
  pill: {
    minHeight: 38,
    paddingHorizontal: 16,
    borderRadius: 19,
    justifyContent: 'center',
    backgroundColor: 'rgba(255,255,255,0.78)',
    borderWidth: 1,
    borderColor: 'rgba(203,213,225,0.9)',
  },
  pillText: {
    color: moodColors.ink,
    fontWeight: '800',
  },
  hero: {
    minHeight: 286,
    overflow: 'hidden',
    borderRadius: 18,
    padding: 18,
    backgroundColor: '#E8F4F4',
    borderWidth: 1,
    borderColor: 'rgba(120,139,163,0.32)',
    shadowColor: '#1F2937',
    shadowOpacity: 0.18,
    shadowRadius: 28,
    shadowOffset: { width: 0, height: 18 },
    elevation: 5,
  },
  skyBand: {
    position: 'absolute',
    left: 0,
    right: 0,
    top: 0,
    height: 96,
    backgroundColor: '#17263A',
  },
  sun: {
    position: 'absolute',
    right: 34,
    top: 34,
    width: 62,
    height: 62,
    borderRadius: 31,
    backgroundColor: '#F4C95D',
  },
  rainLayer: {
    position: 'absolute',
    left: 0,
    right: 0,
    top: 18,
    height: 120,
  },
  rainLine: {
    position: 'absolute',
    top: 28,
    width: 3,
    height: 32,
    borderRadius: 2,
    backgroundColor: 'rgba(96,165,250,0.56)',
    transform: [{ rotate: '18deg' }],
  },
  eyebrow: {
    color: '#8A5A16',
    fontSize: 12,
    fontWeight: '900',
  },
  heroTitle: {
    marginTop: 8,
    color: moodColors.ink,
    fontSize: 34,
    fontWeight: '900',
  },
  heroCopy: {
    width: '78%',
    marginTop: 8,
    color: '#475569',
    fontSize: 15,
    lineHeight: 22,
  },
  metricRow: {
    flexDirection: 'row',
    gap: 8,
    marginTop: 18,
  },
  metric: {
    flex: 1,
    minHeight: 64,
    padding: 10,
    borderRadius: 12,
    backgroundColor: 'rgba(255,255,255,0.72)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.78)',
  },
  metricTitle: {
    color: moodColors.muted,
    fontSize: 11,
    fontWeight: '800',
  },
  metricValue: {
    marginTop: 6,
    color: moodColors.ink,
    fontSize: 18,
    fontWeight: '900',
  },
  moodStatus: {
    marginTop: 10,
    padding: 11,
    borderRadius: 14,
    backgroundColor: 'rgba(255,255,255,0.68)',
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  moodLabel: {
    color: moodColors.muted,
    fontSize: 12,
    fontWeight: '900',
  },
  moodText: {
    maxWidth: 230,
    marginTop: 4,
    color: moodColors.ink,
    fontSize: 14,
    fontWeight: '700',
  },
  steadyBadge: {
    width: 44,
    height: 44,
    borderRadius: 22,
    borderWidth: 2,
    borderColor: 'rgba(15,118,110,0.34)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  steadyText: {
    color: moodColors.teal,
    fontWeight: '900',
  },
  scriptRow: {
    flexDirection: 'row',
    gap: 8,
    marginTop: 14,
  },
  scriptCard: {
    flex: 1,
    minHeight: 78,
    overflow: 'hidden',
    padding: 10,
    borderRadius: 14,
    backgroundColor: moodColors.panel,
  },
  scriptRail: {
    position: 'absolute',
    left: 0,
    top: 0,
    bottom: 0,
    width: 4,
  },
  scriptTime: {
    color: moodColors.ink,
    fontSize: 18,
    fontWeight: '900',
  },
  scriptTitle: {
    marginTop: 6,
    color: moodColors.muted,
    fontSize: 11,
    fontWeight: '900',
  },
  scriptCopy: {
    marginTop: 3,
    color: '#475569',
    fontSize: 11,
  },
  card: {
    marginTop: 14,
    padding: 14,
    borderRadius: 18,
    backgroundColor: 'rgba(255,255,255,0.82)',
    borderWidth: 1,
    borderColor: 'rgba(203,213,225,0.9)',
  },
  sectionTitle: {
    color: moodColors.ink,
    fontSize: 18,
    fontWeight: '900',
  },
  subtle: {
    marginTop: 6,
    color: moodColors.muted,
    fontSize: 14,
    lineHeight: 20,
  },
  weatherRow: {
    flexDirection: 'row',
    gap: 8,
    marginTop: 12,
  },
  weatherHour: {
    flex: 1,
    minHeight: 88,
    overflow: 'hidden',
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#F8FBFF',
    borderWidth: 1,
    borderColor: '#DBE3EE',
  },
  weatherFill: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(96,165,250,0.18)',
  },
  weatherTime: {
    color: moodColors.ink,
    fontSize: 12,
    fontWeight: '900',
  },
  weatherIcon: {
    marginTop: 5,
    color: moodColors.blue,
    fontSize: 18,
    fontWeight: '900',
  },
  weatherChance: {
    marginTop: 5,
    color: moodColors.muted,
    fontSize: 12,
    fontWeight: '700',
  },
  alarmTime: {
    marginTop: 4,
    color: moodColors.teal,
    fontSize: 34,
    fontWeight: '900',
  },
  map: {
    height: 180,
    marginTop: 12,
    overflow: 'hidden',
    borderRadius: 18,
    backgroundColor: '#DDECF1',
    borderWidth: 1,
    borderColor: '#C9D6E6',
  },
  mapRoadOne: {
    position: 'absolute',
    left: 34,
    top: 115,
    width: 220,
    height: 9,
    borderRadius: 8,
    backgroundColor: '#F1EACB',
    transform: [{ rotate: '-17deg' }],
  },
  mapRoadTwo: {
    position: 'absolute',
    left: 124,
    top: 62,
    width: 170,
    height: 9,
    borderRadius: 8,
    backgroundColor: '#F1EACB',
    transform: [{ rotate: '24deg' }],
  },
  routeLine: {
    position: 'absolute',
    left: 72,
    top: 115,
    width: 210,
    height: 5,
    borderRadius: 5,
    backgroundColor: moodColors.teal,
    transform: [{ rotate: '-22deg' }],
  },
  pin: {
    position: 'absolute',
    width: 24,
    height: 24,
    borderRadius: 12,
    borderWidth: 4,
    borderColor: '#FFFFFF',
  },
  pinStart: {
    left: 66,
    top: 104,
    backgroundColor: moodColors.teal,
  },
  pinEnd: {
    right: 62,
    top: 38,
    backgroundColor: moodColors.blue,
  },
  primaryButton: {
    minHeight: 46,
    marginTop: 12,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: moodColors.teal,
  },
  primaryButtonText: {
    color: '#FFFFFF',
    fontWeight: '900',
  },
  authHero: {
    minHeight: 190,
    padding: 18,
    borderRadius: 18,
    backgroundColor: '#E8F4F4',
    borderWidth: 1,
    borderColor: 'rgba(120,139,163,0.3)',
  },
  authTitle: {
    marginTop: 8,
    color: moodColors.ink,
    fontSize: 30,
    fontWeight: '900',
    lineHeight: 34,
  },
  authCopy: {
    width: '82%',
    marginTop: 9,
    color: '#475569',
    fontSize: 15,
    lineHeight: 22,
  },
  formCard: {
    marginTop: 14,
    padding: 14,
    borderRadius: 18,
    backgroundColor: moodColors.panel,
    borderWidth: 1,
    borderColor: 'rgba(203,213,225,0.9)',
  },
  formTitle: {
    color: moodColors.ink,
    fontSize: 22,
    fontWeight: '900',
    marginBottom: 10,
  },
  input: {
    minHeight: 46,
    marginTop: 9,
    paddingHorizontal: 12,
    borderRadius: 14,
    backgroundColor: '#FFFFFF',
    borderWidth: 1,
    borderColor: 'rgba(203,213,225,0.95)',
  },
  linkText: {
    marginTop: 13,
    color: moodColors.teal,
    textAlign: 'center',
    fontWeight: '900',
  },
  note: {
    marginTop: 12,
    color: moodColors.muted,
    fontSize: 12,
    lineHeight: 18,
  },
});
