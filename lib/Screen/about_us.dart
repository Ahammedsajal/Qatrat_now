import 'dart:async';
import 'package:customer/Helper/Color.dart';
import 'package:customer/Helper/Session.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:url_launcher/url_launcher.dart';
import '../Helper/String.dart';
import '../ui/styles/DesignConfig.dart';
import '../ui/widgets/AppBtn.dart';
import '../ui/widgets/SimpleAppBar.dart';
import '../utils/blured_router.dart';
import 'HomePage.dart';

class AboutUs extends StatefulWidget {
  final String? title;
  final bool fromTab; // 👈 NEW: flag to detect Dashboard tab usage

  const AboutUs({super.key, this.title, this.fromTab = false});

  static Route route(RouteSettings settings) {
    final Map? arguments = settings.arguments as Map?;
    return BlurredRouter(
      builder: (context) => AboutUs(
        title: arguments?['title'],
        fromTab: false, // 👈 this is when it's opened from My Profile
      ),
    );
  }

  @override
  State<AboutUs> createState() => _AboutUsState();
}

class _AboutUsState extends State<AboutUs> with TickerProviderStateMixin {
  bool _isLoading = true;
  String? content;
  bool _isNetworkAvail = true;
  AnimationController? buttonController;
  Animation? buttonSqueezeanimation;

  @override
  void initState() {
    super.initState();
    getSetting();

    buttonController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    buttonSqueezeanimation = Tween(
      begin: deviceWidth! * 0.7,
      end: 50.0,
    ).animate(
      CurvedAnimation(
        parent: buttonController!,
        curve: const Interval(0.0, 0.150),
      ),
    );
  }

  Future<void> getSetting() async {
  _isNetworkAvail = await isNetworkAvailable();
  if (_isNetworkAvail) {
    try {
      final parameter = {TYPE: ABOUT_US};
      final getdata = await apiBaseHelper.postAPICall(getSettingApi, parameter);
      final bool error = getdata["error"];

      if (!error) {
        // Detect current language
        Locale currentLocale = Localizations.localeOf(context);
        String langCode = currentLocale.languageCode;

        // Use about_us_ar if Arabic, otherwise default to about_us
        String key = langCode == 'ar' ? 'about_us_ar' : 'about_us';

        // Fetch content from the response
        String rawContent = getdata["data"][key][0].toString();
        content = rawContent;
      } else {
        setSnackbar(getTranslated(context, getdata["message"]) ?? getdata["message"], context);
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } on TimeoutException catch (_) {
      setSnackbar(getTranslated(context, 'somethingMSg')!, context);
      setState(() {
        _isLoading = false;
      });
    }
  } else {
    setState(() {
      _isNetworkAvail = false;
      _isLoading = false;
    });
  }
}


  Future<void> _playAnimation() async {
    try {
      await buttonController!.forward();
    } on TickerCanceled {
      return;
    }
  }

  Widget noInternet(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          noIntImage(),
          noIntText(context),
          noIntDec(context),
          AppBtn(
            title: getTranslated(context, 'TRY_AGAIN_INT_LBL'),
            btnAnim: buttonSqueezeanimation,
            btnCntrl: buttonController,
            onBtnSelected: () async {
              _playAnimation();
              Future.delayed(const Duration(seconds: 2)).then((_) async {
                _isNetworkAvail = await isNetworkAvailable();
                if (_isNetworkAvail) {
                  Navigator.pushReplacement(
                    context,
                    CupertinoPageRoute(builder: (BuildContext context) => super.widget),
                  );
                } else {
                  await buttonController!.reverse();
                  if (mounted) {
                    setState(() {
                      getSetting();
                    });
                  }
                }
              });
            },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    buttonController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget contentWidget = _isLoading
        ? getProgress(context)
        : _isNetworkAvail
            ? SingleChildScrollView(
                padding: const EdgeInsets.all(12.0),
                child: HtmlWidget(
                  content ?? "",
                  onTapUrl: (url) async {
                    if (await canLaunchUrl(Uri.parse(url))) {
                      await launchUrl(Uri.parse(url));
                      return true;
                    }
                    return false;
                  },
                  textStyle: TextStyle(color: Theme.of(context).colorScheme.fontColor),
                ),
              )
            : noInternet(context);

    // If AboutUs is part of a Dashboard tab, skip Scaffold/AppBar
   if (widget.fromTab) {
  return SafeArea(
    bottom: true, // ensures content stays above tab bar
    child: Padding(
      padding: const EdgeInsets.only(bottom: 60.0), // adjust if your bottom bar height is different
      child: contentWidget,
    ),
  );
}


    // Else use full screen with AppBar
    return Scaffold(
      appBar: getSimpleAppBar(widget.title ?? getTranslated(context, 'ABOUT_LBL')!, context),
      body: contentWidget,
    );
  }
}
