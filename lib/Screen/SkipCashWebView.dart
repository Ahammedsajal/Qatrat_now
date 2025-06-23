import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../utils/Hive/hive_utils.dart';
import '../Provider/CartProvider.dart';
import '../app/routes.dart';

class SkipCashWebView extends StatefulWidget {
  final String payUrl;
  final String paymentId;
  final Future<void> Function(String message) onSuccess;
  final Function(String error) onError;

  const SkipCashWebView({
    super.key,
    required this.payUrl,
    required this.paymentId,
    required this.onSuccess,
    required this.onError,
  });

  @override
  State<SkipCashWebView> createState() => _SkipCashWebViewState();
}

class _SkipCashWebViewState extends State<SkipCashWebView> {
  late final WebViewController _controller;
  bool _isWebViewReady = false;

  final String? jwtToken = HiveUtils.getJWT();

  @override
  void initState() {
    super.initState();
    final PlatformWebViewControllerCreationParams params =
        const PlatformWebViewControllerCreationParams();
    _controller = WebViewController.fromPlatformCreationParams(params);

    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final url = request.url;
            // Listen for your custom deep link
            if (url.startsWith('qatratkheir://order-success')) {
              // Extract order_id from url if needed
              // You can also call widget.onSuccess here if you want
              // Optionally, clear the cart and navigate
              Provider.of<CartProvider>(context, listen: false).clearCart();
              Navigator.of(context).pushNamedAndRemoveUntil(
                Routers.dashboardScreen, // Use your router constants
                (route) => route.isFirst,
              );
              // Cancel loading this URL in WebView
              return NavigationDecision.prevent;
            } else if (url.startsWith('qatratkheir://payment-failed')) {
              widget.onError('Payment failed or was cancelled.');
              Navigator.of(context).pop(); // Close the WebView
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (url) {
            setState(() => _isWebViewReady = true);
          },
          onWebResourceError: (error) {
            widget.onError('WebView error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.payUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("SkipCash Payment")),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (!_isWebViewReady)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
