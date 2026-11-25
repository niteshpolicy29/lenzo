import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'screens/camera_screen.dart';
import 'screens/onboarding_screens.dart';
import 'services/face_repository.dart';
import 'services/onboarding_store.dart';
import 'theme/lenzo_theme.dart';
import 'widgets/lenzo_ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Portrait only keeps camera frame rotation and overlay math simple.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(lenzoSystemUi);
  runApp(const LenzoApp());
}

class LenzoApp extends StatelessWidget {
  const LenzoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lenzo',
      debugShowCheckedModeBanner: false,
      theme: Lenzo.theme(),
      home: const _Startup(),
    );
  }
}

/// Loads the database, face model and onboarding progress, then opens
/// onboarding for a new user or the camera for everyone else.
class _Startup extends StatefulWidget {
  const _Startup();

  @override
  State<_Startup> createState() => _StartupState();
}

class _StartupState extends State<_Startup> {
  final _store = OnboardingStore();
  late final Future<(FaceRepository, OnboardingProgress?)> _load = () async {
    final results = await Future.wait<Object?>([
      FaceRepository.create(),
      _store.load(),
    ]);
    return (results[0] as FaceRepository, results[1] as OnboardingProgress?);
  }();

  /// Set once onboarding finishes in this session.
  bool _finished = false;

  void _onboardingFinished(String? name) {
    setState(() => _finished = true);
    if (name != null) showLenzoSuccess(context, 'Welcome to Lenzo, $name');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(FaceRepository, OnboardingProgress?)>(
      future: _load,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Failed to start: ${snap.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        if (!snap.hasData) return const _Splash();
        final (repo, progress) = snap.data!;
        final step = _finished
            ? OnboardingStep.done
            : resolveOnboardingStep(
                hasOwner: repo.ownerId != null,
                progress: progress,
              );
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 420),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: ScaleTransition(
              scale: Tween(begin: 0.98, end: 1.0).animate(a),
              child: child,
            ),
          ),
          child: step == OnboardingStep.done
              ? CameraScreen(key: const ValueKey('scanner'), repo: repo)
              : OnboardingFlow(
                  key: const ValueKey('onboarding'),
                  repo: repo,
                  store: _store,
                  initialStep: step,
                  initialProgress: progress ?? const OnboardingProgress(),
                  onFinished: _onboardingFinished,
                ),
        );
      },
    );
  }
}

/// Shown while the database and face model load. Matches the Android splash
/// (logo centred on dark green, 220 wide) so the hand-over is seamless, with
/// a small progress indicator below.
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    const logoWidth = 220.0;
    return const Scaffold(
      backgroundColor: Lenzo.background,
      body: Stack(
        alignment: Alignment.center,
        children: [
          LenzoBrandLogo(height: logoWidth / LenzoBrandLogo.aspectRatio),
          Align(
            alignment: Alignment(0, 0.3),
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Lenzo.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
