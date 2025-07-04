  import 'dart:async';
  import 'dart:convert';
  import 'dart:io';
  import 'package:collection/src/iterable_extensions.dart';
import 'package:flutter/services.dart';
  // At the top of Cart.dart
// import removed because payment selection screen is no longer used
// import 'package:customer/Screen/Payment.dart' hide isTimeSlot;
import 'package:customer/Screen/SkipCashWebView.dart';
import 'package:logging/logging.dart';
  import 'package:crypto/crypto.dart';
  import 'package:customer/Helper/Session.dart';
  import 'package:customer/Helper/SqliteData.dart';
  import 'package:customer/Helper/cart_var.dart';
  import 'package:customer/Provider/CartProvider.dart';
  import 'package:customer/Provider/SettingProvider.dart';
  import 'package:customer/Provider/UserProvider.dart';
  import 'package:customer/app/routes.dart';
  import 'package:file_picker/file_picker.dart';
  import 'package:flutter/cupertino.dart';
  import 'package:flutter/material.dart';
  import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_svg/svg.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:my_fatoorah/my_fatoorah.dart';
import 'package:intl/intl.dart';
  import 'package:provider/provider.dart';
  import '../../Helper/ApiBaseHelper.dart';
  import '../../Helper/Color.dart';
  import '../../Helper/Constant.dart';
import 'package:customer/Helper/String.dart' hide currencySymbol;
  import '../../Model/Model.dart';
  import '../../cubits/FetchMosquesCubit.dart';
  import '../../Model/Section_Model.dart';
  import '../../Model/User.dart';
  import '../../Provider/MyFatoraahPaymentProvider.dart';
  import '../../ui/styles/DesignConfig.dart';
  import '../../ui/styles/Validators.dart';
import '../../ui/widgets/AppBtn.dart';
import '../../ui/widgets/DiscountLabel.dart';
import '../../ui/widgets/SimBtn.dart';
import '../../ui/widgets/SimpleAppBar.dart';
import '../../ui/widgets/Stripe_Service.dart';
import '../../ui/widgets/PaymentRadio.dart';
  import '../HomePage.dart';
  import 'package:flutter_bloc/flutter_bloc.dart';
import '../../utils/Hive/hive_utils.dart';
  import '../PaypalWebviewActivity.dart';
  import '../qatar_mosques.dart';
  import '../midtransWebView.dart';
  import '../../Provider/MosqueProvider.dart';
  import '../../app/curreny_converter.dart';
  import '../../Model/MosqueModel.dart';
  part './segments/methods.dart';


  class Cart extends StatefulWidget {
    final bool fromBottom;
    final bool buyNow;
    const Cart({super.key, required this.fromBottom, this.buyNow = false});
    @override
    State<StatefulWidget> createState() => StateCart();
  }

  class StateCart extends State<Cart> with TickerProviderStateMixin {
    Future<Map<String, dynamic>> updateOrderStatus({
      required String status,
      required String orderID,
    }) async {
      final parameter = {ORDER_ID: orderID, STATUS: status};
      final Logger log = Logger('Cart.dart');
      final result = await ApiBaseHelper().postAPICall(updateOrderApi, parameter);
      return {'error': result['error'], 'message': result['message']};
    }
    
    List<Model> deliverableList = [];
    bool _isCartLoad = true;
    
    bool _placeOrder = true;
    bool _isSaveLoad = true;
    MosqueModel? selectedMosque;

    Animation? buttonSqueezeanimation;
    AnimationController? buttonController;
    bool _isNetworkAvailable = true;
    TextEditingController promoCodeController = TextEditingController();
    final List<TextEditingController> _controller = [];
    final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
        GlobalKey<RefreshIndicatorState>();
    String? msg;
    bool _isLoading = true;
    final Logger _log = Logger('Cart.dart');
    TextEditingController noteC = TextEditingController();
    StateSetter? checkoutState;
    bool deliverable = true;
    bool saveLater = false;
    bool addCart = false;
    bool buynow = false;
    final ScrollController _scrollControllerOnCartItems = ScrollController();
    final ScrollController _scrollControllerOnSaveForLaterItems =
        ScrollController();
        
    TextEditingController emailController = TextEditingController();
      TextEditingController mobileController = TextEditingController();

    List<String> productIds = [];
    List<String> proVarIds = [];
    DatabaseHelper db = DatabaseHelper();
    bool isAvailable = true;
    String razorpayOrderId = '';
    String? rozorpayMsg;
    // ───────────────────────────────
    // Time slot related variables (moved from Payment screen)
    List<Model> timeSlotList = [];
    List<RadioModel> timeModel = [];
    String? startingDate;
    String? allowDay;
    bool _isTimeSlotLoading = true;
    @override
    void setState(VoidCallback fn) {
      if (mounted) {
        super.setState(fn);
      }
    }

    Future<void> _optimisticQtyChange(
      int i,
      int d,
      List<SectionModel> l,
    ) async {
      if (context.read<CartProvider>().isProgress) return;
      int nq = int.parse(l[i].qty!) + d;
      if (nq < 0) nq = 0;
      final min = l[i].productList![0].minOrderQuntity!;
      if (nq != 0 && nq < min) {
        setSnackbar("${getTranslated(context, 'MIN_MSG')}$min", context);
        return;
      }
      final unit = double.parse(l[i].perItemPrice!);
      final snapQty = l[i].qty;
      final snapItemTotal = l[i].perItemTotal;
      final snapPrice = originalPrice;
      l[i]
        ..qty = nq.toString()
        ..perItemTotal = (unit * nq).toString();
      originalPrice += d * unit;
      totalPrice = originalPrice;
      setState(() {});
      checkoutState?.call(() {});
      try {
        final r = await apiBaseHelper.postAPICall(manageCartApi, {
          PRODUCT_VARIENT_ID: l[i].varientId,
          USER_ID: context.read<UserProvider>().userId,
          QTY: nq.toString(),
        });
        if (r['error']) throw r['message'];
        originalPrice = double.parse(r['data'][SUB_TOTAL]);
        totalPrice = originalPrice;
        if (nq == 0) l.removeAt(i);
      } catch (e) {
        l[i]
          ..qty = snapQty
          ..perItemTotal = snapItemTotal;
        originalPrice = totalPrice = snapPrice;
        setSnackbar(e.toString(), context);
      }
      setState(() {});
      checkoutState?.call(() {});
    }
    @override
    void initState() {
      super.initState();
      prescriptionImages.clear();
      
      callApi();
      if (context.read<UserProvider>().email != '') {
        emailController.text = context.read<UserProvider>().email;
      }
      
     // Initialize mobile controller with the current mobile number
    mobileController.text = context.read<UserProvider>().mobile;
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
          curve: const Interval(
            0.0,
            0.150,
          ),
        ),
      );
      
    }

    callApi() async {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<CartProvider>().setProgress(false);
        }
      });
      if (context.read<UserProvider>().userId != "") {
        _getCart("0");
        _getSaveLater("1");
      } else {
        productIds = (await db.getCart())!;
        _getOfflineCart();
        proVarIds = (await db.getSaveForLater())!;
        _getOffSaveLater();
      }
    }

    Future<void> _refresh() async {
      if (mounted) {
        setState(() {
          _isCartLoad = true;
          _isSaveLoad = true;
        });
      }
      isAvailable = true;
      if (context.read<UserProvider>().userId != "") {
        clearCart();
        _getCart("0");
        return _getSaveLater("1");
      } else {
        originalPrice = 0;
        saveLaterList.clear();
        productIds = (await db.getCart())!;
        await _getOfflineCart();
        proVarIds = (await db.getSaveForLater())!;
        await _getOffSaveLater();
      }
    }

    clearCart() {
      totalPrice = 0;
      originalPrice = 0;
      taxPersontage = 0;
      deliveryCharge = 0;
      addressList.clear();
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        context.read<CartProvider>().setCartlist([]);
        context.read<CartProvider>().setProgress(false);
      });
      promoAmount = 0;
      remWalBal = 0;
      usedBalance = 0;
      paymentMethod = '';
      isPromoValid = false;
      isUseWallet = false;
      isPayLayShow = true;
      selectedMethod = null;
      codDeliverChargesOfShipRocket = 0.0;
      prePaidDeliverChargesOfShipRocket = 0.0;
      isLocalDelCharge = null;
      shipRocketDeliverableDate = '';
    }

    @override
    void dispose() {
      buttonController!.dispose();
      promoCodeController.dispose();
      emailController.dispose();
      _scrollControllerOnCartItems.removeListener(() {});
      _scrollControllerOnSaveForLaterItems.removeListener(() {});

      for (int i = 0; i < _controller.length; i++) {
        _controller[i].dispose();
      }

      super.dispose();
    }

    updatePromo(String promo) {
      setState(() {
        isPromoLen = false;
        promoCodeController.text = promo;
      });
    }

    Future<void> getShipRocketDeliveryCharge(String shipRocket, int from) async {
      _isNetworkAvailable = await isNetworkAvailable();

      if (_isNetworkAvailable) {
        if (addressList.isNotEmpty) {
          try {
            context.read<CartProvider>().setProgress(true);

            final parameter = {
              USER_ID: context.read<UserProvider>().userId,
              ADD_ID: addressList[selectedAddress!].id,
              "only_delivery_charge": shipRocket,
              SUB_TOTAL: originalPrice.toString(),
            };

            apiBaseHelper.postAPICall(getCartApi, parameter).then(
              (getdata) {
                final bool error = getdata["error"];
                final String? msg = getdata["message"];
                final data = getdata["data"];

                context.read<CartProvider>().setProgress(false);

                if (error) {
                  setSnackbar(msg.toString(), context);
                  deliverable = true;
                } else {
                  if (shipRocket == "1") {
                    codDeliverChargesOfShipRocket =
                        double.parse(data['delivery_charge_with_cod'].toString());

                    prePaidDeliverChargesOfShipRocket = double.parse(
                      data['delivery_charge_without_cod'].toString(),
                    );

                    if (codDeliverChargesOfShipRocket > 0 &&
                        prePaidDeliverChargesOfShipRocket > 0) {
                      isLocalDelCharge = false;
                    } else {
                      isLocalDelCharge = true;
                    }

                    shipRocketDeliverableDate = data['estimate_date'] ?? "";

                    if (paymentMethod == '') {
                      deliveryCharge = codDeliverChargesOfShipRocket;
                    } else {
                      if (paymentMethod == getTranslated(context, 'COD_LBL')) {
                        deliveryCharge = codDeliverChargesOfShipRocket;
                      } else {
                        deliveryCharge = prePaidDeliverChargesOfShipRocket;
                      }
                    }
                  } else {
                    isLocalDelCharge = true;
                    deliveryCharge = double.parse(getdata[DEL_CHARGE]);
                  }

                  deliverable = true;
                }
                print("deliverycharge-->$deliveryCharge");
                context.read<CartProvider>().setProgress(false);

                setState(() {});

                if (mounted) {
                  checkoutState?.call(() {});
                }
              },
              onError: (error) {
                setSnackbar(error.toString(), context);
              },
            );
          } on TimeoutException catch (_) {
            setSnackbar(getTranslated(context, 'somethingMSg')!, context);
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _isNetworkAvailable = false;
          });
        }
      }
    }

    @override
    Widget build(BuildContext context) {
      deviceHeight = MediaQuery.of(context).size.height;
      deviceWidth = MediaQuery.of(context).size.width;
      return Scaffold(
        
          appBar: widget.fromBottom
              ? null
              : getSimpleAppBar(getTranslated(context, 'CART')!, context),
          body: SafeArea(
         child: Consumer<UserProvider>(
            builder: (context, data, child) {
              return _isNetworkAvailable
                  ? context.read<UserProvider>().userId != ""
                      ? Stack(
                          children: <Widget>[
                            _showContent(context),
                            Selector<CartProvider, bool>(
                              builder: (context, data, child) {
                                return showCircularProgress(
                                  context,
                                  data,
                                  Theme.of(context).colorScheme.primarytheme,
                                );
                              },
                              selector: (_, provider) => provider.isProgress,
                            ),
                          ],
                        )
                      : Stack(
                          children: <Widget>[
                            _showContent1(context),
                            Selector<CartProvider, bool>(
                              builder: (context, data, child) {
                                return showCircularProgress(
                                  context,
                                  data,
                                  Theme.of(context).colorScheme.primarytheme,
                                );
                              },
                              selector: (_, provider) => provider.isProgress,
                            ),
                          ],
                        )
                  : noInternet(
                      context,
                      buttonController: buttonController,
                      buttonSqueezeanimation: buttonSqueezeanimation,
                      onButtonClicked: (internetAvailable) {
                        _isNetworkAvailable = internetAvailable;
                        callApi();
                        setState(() {});
                      },
                      onNetworkNavigationWidget: super.widget,
                    );
            },
          ),
        ),
      );
    }

    addAndRemoveQty(
      String qty,
      int from,
      int totalLen,
      int index,
      double price,
      int selectedPos,
      double total,
      List<SectionModel> cartList,
      int itemCounter,
    ) async {
      if (from == 1) {
        if (int.parse(qty) >= totalLen) {
          setSnackbar("${getTranslated(context, 'MAXQTY')!}  $qty", context);
        } else {
          db.updateCart(
            cartList[index].id!,
            cartList[index].productList![0].prVarientList![selectedPos].id!,
            (int.parse(qty) + itemCounter).toString(),
          );
          context.read<CartProvider>().updateCartItem(
                cartList[index].productList![0].id,
                (int.parse(qty) + itemCounter).toString(),
                selectedPos,
                cartList[index].productList![0].prVarientList![selectedPos].id!,
              );
          originalPrice = originalPrice + price;
          setState(() {});
        }
      } else if (from == 2) {
        if (int.parse(qty) <= cartList[index].productList![0].minOrderQuntity!) {
          db.updateCart(
            cartList[index].id!,
            cartList[index].productList![0].prVarientList![selectedPos].id!,
            itemCounter.toString(),
          );
          context.read<CartProvider>().updateCartItem(
                cartList[index].productList![0].id,
                itemCounter.toString(),
                selectedPos,
                cartList[index].productList![0].prVarientList![selectedPos].id!,
              );
          setState(() {});
        } else {
          db.updateCart(
            cartList[index].id!,
            cartList[index].productList![0].prVarientList![selectedPos].id!,
            (int.parse(qty) - itemCounter).toString(),
          );
          context.read<CartProvider>().updateCartItem(
                cartList[index].productList![0].id,
                (int.parse(qty) - itemCounter).toString(),
                selectedPos,
                cartList[index].productList![0].prVarientList![selectedPos].id!,
              );
          originalPrice = originalPrice - price;
          setState(() {});
        }
      } else {
        db.updateCart(
          cartList[index].id!,
          cartList[index].productList![0].prVarientList![selectedPos].id!,
          qty,
        );
        context.read<CartProvider>().updateCartItem(
              cartList[index].productList![0].id,
              qty,
              selectedPos,
              cartList[index].productList![0].prVarientList![selectedPos].id!,
            );
        originalPrice = originalPrice - total + (int.parse(qty) * price);
        setState(() {});
      }
    }

    Widget listItem(int index, List<SectionModel> cartList) {
      int selectedPos = 0;
      for (int i = 0;
          i < cartList[index].productList![0].prVarientList!.length;
          i++) {
        if (cartList[index].varientId ==
            cartList[index].productList![0].prVarientList![i].id) {
          selectedPos = i;
        }
      }
      String? offPer;
      double price = double.parse(
        cartList[index].productList![0].prVarientList![selectedPos].disPrice!,
      );
      if (price == 0) {
        price = double.parse(
          cartList[index].productList![0].prVarientList![selectedPos].price!,
        );
      } else {
        final double off = (double.parse(
              cartList[index].productList![0].prVarientList![selectedPos].price!,
            )) -
            price;
        offPer = (off *
                100 /
                double.parse(
                  cartList[index]
                      .productList![0]
                      .prVarientList![selectedPos]
                      .price!,
                ))
            .toStringAsFixed(2);
      }
      cartList[index].perItemPrice = price.toString();
      if (_controller.length < index + 1) {
        _controller.add(TextEditingController());
      }
      if (cartList[index].productList![0].availability != "0") {
        cartList[index].perItemTotal =
            ((cartList[index].productList![0].isSalesOn == "1"
                        ? double.parse(
                            cartList[index]
                                .productList![0]
                                .prVarientList![selectedPos]
                                .saleFinalPrice!,
                          )
                        : price) *
                    double.parse(cartList[index].qty!))
                .toString();
        _controller[index].text = cartList[index].qty!;
      }
      List att = [];
      List val = [];
      if (cartList[index].productList![0].prVarientList![selectedPos].attr_name !=
          "") {
        att = cartList[index]
            .productList![0]
            .prVarientList![selectedPos]
            .attr_name!
            .split(',');
        val = cartList[index]
            .productList![0]
            .prVarientList![selectedPos]
            .varient_value!
            .split(',');
      }
      if (cartList[index].productList![0].attributeList!.isEmpty) {
        if (cartList[index].productList![0].availability == "0") {
          isAvailable = false;
        }
      } else {
        if (cartList[index]
                .productList![0]
                .prVarientList![selectedPos]
                .availability ==
            "0") {
          isAvailable = false;
        }
      }
      final double total = (cartList[index].productList![0].isSalesOn == "1"
              ? double.parse(
                  cartList[index]
                      .productList![0]
                      .prVarientList![selectedPos]
                      .saleFinalPrice!,
                )
              : price) *
          double.parse(
            cartList[index]
                .productList![0]
                .prVarientList![selectedPos]
                .cartCount!,
          );
      return Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 1.0,
        ),
        child: Card(
          elevation: 0.1,
          child: Column(
            children: [
              InkWell(
                child: Row(
                  children: <Widget>[
                    Hero(
                      tag: "$cartHero$index${cartList[index].productList![0].id}",
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(7.0),
                              child: Stack(
                                children: [
                                  networkImageCommon(
                                    cartList[index].productList![0].type ==
                                                "variable_product" &&
                                            cartList[index]
                                                .productList![0]
                                                .prVarientList![selectedPos]
                                                .images!
                                                .isNotEmpty
                                        ? cartList[index]
                                            .productList![0]
                                            .prVarientList![selectedPos]
                                            .images![0]
                                        : cartList[index].productList![0].image!,
                                    100,
                                    false,
                                    height: 100,
                                    width: 100,
                                  ),
                                  Positioned.fill(
                                    child: cartList[index]
                                                .productList![0]
                                                .prVarientList![selectedPos]
                                                .availability ==
                                            "0"
                                        ? Container(
                                            height: 55,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .white70,
                                            padding: const EdgeInsets.all(2),
                                            child: Center(
                                              child: Text(
                                                getTranslated(
                                                  context,
                                                  'OUT_OF_STOCK_LBL',
                                                )!,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall!
                                                    .copyWith(
                                                      color: Colors.red,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ],
                              ),
                            ),
                            if (offPer != null)
                              getDiscountLabel(
                                cartList[index].productList![0].isSalesOn == "1"
                                    ? double.parse(
                                        cartList[index].productList![0].saleDis!,
                                      ).toStringAsFixed(2)
                                    : offPer,
                              )
                            else
                              const SizedBox.shrink(),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsetsDirectional.all(8.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                      top: 5.0,
                                    ),
                                    child: Text(
  // Attempt to translate using product name as the key:
  getTranslated(context, cartList[index].productList![0].name!) 
    // Fallback: if no translation found, display the original name
    ?? cartList[index].productList![0].name!,  
  style: Theme.of(context)
      .textTheme
      .titleMedium!
      .copyWith(
        color: Theme.of(context).colorScheme.fontColor,
        fontSize: 14,
      ),
  maxLines: 2,
  overflow: TextOverflow.ellipsis,
),

                                  ),
                                ),
                                InkWell(
                                  child: Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                      start: 8.0,
                                      end: 8,
                                      bottom: 8,
                                    ),
                                    child: Icon(
                                      Icons.close,
                                      size: 20,
                                      color:
                                          Theme.of(context).colorScheme.fontColor,
                                    ),
                                  ),
                                  onTap: () async {
                                    if (context.read<CartProvider>().isProgress ==
                                        false) {
                                      if (context.read<UserProvider>().userId !=
                                          "") {
                                        deleteProductFromCart(
                                          index,
                                          1,
                                          cartList,
                                          selectedPos,
                                        );
                                      } else {
                                        db.removeCart(
                                          cartList[index]
                                              .productList![0]
                                              .prVarientList![selectedPos]
                                              .id!,
                                          cartList[index].id!,
                                          context,
                                        );
                                        cartList.removeWhere(
                                          (item) =>
                                              item.varientId ==
                                              cartList[index]
                                                  .productList![0]
                                                  .prVarientList![selectedPos]
                                                  .id!,
                                        );
                                        originalPrice = originalPrice - total;
                                        productIds = (await db.getCart())!;
                                        setState(() {});
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                            if (cartList[index]
                                        .productList![0]
                                        .prVarientList![selectedPos]
                                        .attr_name !=
                                    null &&
                                cartList[index]
                                    .productList![0]
                                    .prVarientList![selectedPos]
                                    .attr_name!
                                    .isNotEmpty)
                              ListView.builder(
                                physics: const NeverScrollableScrollPhysics(),
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                itemCount: att.length,
                                itemBuilder: (context, index) {
                                  return Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          att[index].trim() + ":",
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall!
                                              .copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .lightBlack,
                                              ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsetsDirectional.only(
                                          start: 5.0,
                                        ),
                                        child: Text(
                                          val[index],
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall!
                                              .copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .lightBlack,
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              )
                            else
                              const SizedBox(),
                            const SizedBox(
                              height: 3,
                            ),
                            Row(
  mainAxisSize: MainAxisSize.min,
  children: <Widget>[
    // If there's an original price (i.e. discount exists), display it with a strikethrough.
    if (offPer != "0.00")
      buildConvertedPrice(
        context,
        double.parse(
          cartList[index]
              .productList![0]
              .prVarientList![selectedPos]
              .price!,
        ),
        isOriginal: true,
      )
    else
      const SizedBox.shrink(),
    // Then display the final (sale) price if applicable,
    // or the regular price if there's no sale.
    buildConvertedPrice(
      context,
      cartList[index].productList![0].isSalesOn == "1"
          ? double.parse(
              cartList[index]
                  .productList![0]
                  .prVarientList![selectedPos]
                  .saleFinalPrice!,
            )
          : price,
    ),
  ],
),

                            const SizedBox(
                              height: 2,
                            ),
                            if (cartList[index].productList![0].availability ==
                                    "1" ||
                                cartList[index].productList![0].stockType == "")
                              Row(
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      InkWell(
                                        child: Card(
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(50),
                                          ),
                                          child: const Padding(
                                            padding: EdgeInsets.all(8.0),
                                            child: Icon(
                                              Icons.remove,
                                              size: 15,
                                            ),
                                          ),
                                        ),
                                        onTap: () {
                                          if (context
                                                  .read<CartProvider>()
                                                  .isProgress ==
                                              false) {
                                            if (context
                                                    .read<UserProvider>()
                                                    .userId !=
                                                "") {
                                              removeFromCart(
                                                index,
                                                false,
                                                cartList,
                                                false,
                                                selectedPos,
                                              );
                                            } else {
                                              if ((int.parse(
                                                    cartList[index]
                                                        .productList![0]
                                                        .prVarientList![
                                                            selectedPos]
                                                        .cartCount!,
                                                  )) >
                                                  1) {
                                                setState(() {
                                                  addAndRemoveQty(
                                                    cartList[index]
                                                        .productList![0]
                                                        .prVarientList![
                                                            selectedPos]
                                                        .cartCount!,
                                                    2,
                                                    cartList[index]
                                                            .productList![0]
                                                            .itemsCounter!
                                                            .length *
                                                        int.parse(
                                                          cartList[index]
                                                              .productList![0]
                                                              .qtyStepSize!,
                                                        ),
                                                    index,
                                                    cartList[index]
                                                                .productList![0]
                                                                .isSalesOn ==
                                                            "1"
                                                        ? double.parse(
                                                            cartList[index]
                                                                .productList![0]
                                                                .prVarientList![
                                                                    selectedPos]
                                                                .saleFinalPrice!,
                                                          )
                                                        : price,
                                                    selectedPos,
                                                    total,
                                                    cartList,
                                                    int.parse(
                                                      cartList[index]
                                                          .productList![0]
                                                          .qtyStepSize!,
                                                    ),
                                                  );
                                                });
                                              }
                                            }
                                          }
                                        },
                                      ),
                                      SizedBox(
                                        width: 37,
                                        height: 20,
                                        child: Stack(
                                          children: [
                                            TextField(
                                              textAlign: TextAlign.center,
                                              readOnly: true,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .fontColor,
                                              ),
                                              controller: _controller[index],
                                              decoration: const InputDecoration(
                                                border: InputBorder.none,
                                              ),
                                            ),
                                            PopupMenuButton<String>(
                                              tooltip: '',
                                              icon: const Icon(
                                                Icons.arrow_drop_down,
                                                size: 1,
                                              ),
                                              onSelected: (String value) {
                                                if (context
                                                        .read<CartProvider>()
                                                        .isProgress ==
                                                    false) {
                                                  if (context
                                                          .read<UserProvider>()
                                                          .userId !=
                                                      "") {
                                                    addToCart(
                                                      index,
                                                      value,
                                                      cartList,
                                                    );
                                                  } else {
                                                    addAndRemoveQty(
                                                      value,
                                                      3,
                                                      cartList[index]
                                                              .productList![0]
                                                              .itemsCounter!
                                                              .length *
                                                          int.parse(
                                                            cartList[index]
                                                                .productList![0]
                                                                .qtyStepSize!,
                                                          ),
                                                      index,
                                                      cartList[index]
                                                                  .productList![0]
                                                                  .isSalesOn ==
                                                              "1"
                                                          ? double.parse(
                                                              cartList[index]
                                                                  .productList![0]
                                                                  .prVarientList![
                                                                      selectedPos]
                                                                  .saleFinalPrice!,
                                                            )
                                                          : price,
                                                      selectedPos,
                                                      total,
                                                      cartList,
                                                      int.parse(
                                                        cartList[index]
                                                            .productList![0]
                                                            .qtyStepSize!,
                                                      ),
                                                    );
                                                  }
                                                }
                                              },
                                              itemBuilder:
                                                  (BuildContext context) {
                                                return cartList[index]
                                                    .productList![0]
                                                    .itemsCounter!
                                                    .map<PopupMenuItem<String>>(
                                                        (String value) {
                                                  return PopupMenuItem(
                                                    value: value,
                                                    child: Text(
                                                      value,
                                                      style: TextStyle(
                                                        color: Theme.of(
                                                          context,
                                                        ).colorScheme.fontColor,
                                                      ),
                                                    ),
                                                  );
                                                }).toList();
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                      InkWell(
                                        child: Card(
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(50),
                                          ),
                                          child: const Padding(
                                            padding: EdgeInsets.all(8.0),
                                            child: Icon(
                                              Icons.add,
                                              size: 15,
                                            ),
                                          ),
                                        ),
                                        onTap: () {
                                          if (context
                                                  .read<CartProvider>()
                                                  .isProgress ==
                                              false) {
                                            if (context
                                                    .read<UserProvider>()
                                                    .userId !=
                                                "") {
                                              addToCart(
                                                index,
                                                (int.parse(
                                                          cartList[index].qty!,
                                                        ) +
                                                        int.parse(
                                                          cartList[index]
                                                              .productList![0]
                                                              .qtyStepSize!,
                                                        ))
                                                    .toString(),
                                                cartList,
                                              );
                                            } else {
                                              addAndRemoveQty(
                                                cartList[index]
                                                    .productList![0]
                                                    .prVarientList![selectedPos]
                                                    .cartCount!,
                                                1,
                                                cartList[index]
                                                        .productList![0]
                                                        .itemsCounter!
                                                        .length *
                                                    int.parse(
                                                      cartList[index]
                                                          .productList![0]
                                                          .qtyStepSize!,
                                                    ),
                                                index,
                                                cartList[index]
                                                            .productList![0]
                                                            .isSalesOn ==
                                                        "1"
                                                    ? double.parse(
                                                        cartList[index]
                                                            .productList![0]
                                                            .prVarientList![
                                                                selectedPos]
                                                            .saleFinalPrice!,
                                                      )
                                                    : price,
                                                selectedPos,
                                                total,
                                                cartList,
                                                int.parse(
                                                  cartList[index]
                                                      .productList![0]
                                                      .qtyStepSize!,
                                                ),
                                              );
                                            }
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              )
                            else
                              const SizedBox.shrink(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                onTap: () {
                  Navigator.pushNamed(
                    context,
                    Routers.productDetails,
                    arguments: {
                      "secPos": 0,
                      "index": index,
                      "list": true,
                      "id": cartList[index].productList![0].id,
                    },
                  );
                },
              ),
              Divider(
                color: Theme.of(context).colorScheme.simmerHigh,
                thickness: 1,
                height: 0,
              ),
              IntrinsicHeight(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: InkWell(
                          onTap: !saveLater &&
                                  !context.read<CartProvider>().isProgress
                              ? () {
                                  if (context.read<UserProvider>().userId != "") {
                                    setState(() {
                                      saveLater = true;
                                    });
                                    saveForLater(
                                      cartList[index]
                                                  .productList![0]
                                                  .availability ==
                                              '0'
                                          ? cartList[index]
                                              .productList![0]
                                              .prVarientList![selectedPos]
                                              .id!
                                          : cartList[index].varientId,
                                      "1",
                                      cartList[index]
                                                  .productList![0]
                                                  .availability ==
                                              "0"
                                          ? "1"
                                          : cartList[index].qty,
                                      double.parse(
                                        cartList[index].perItemTotal!,
                                      ),
                                      cartList[index],
                                      false,
                                      selectedPos,
                                      selIndex: cartList[index]
                                                  .productList![0]
                                                  .availability ==
                                              '0'
                                          ? selectedPos
                                          : null,
                                    );
                                  } else {
                                    if (int.parse(
                                          cartList[index]
                                              .productList![0]
                                              .prVarientList![selectedPos]
                                              .cartCount!,
                                        ) >
                                        0) {
                                      setState(() async {
                                        saveLater = true;
                                        context
                                            .read<CartProvider>()
                                            .setProgress(true);
                                        await saveForLaterFun(
                                          index,
                                          selectedPos,
                                          total,
                                          cartList,
                                        );
                                      });
                                    } else {
                                      context
                                          .read<CartProvider>()
                                          .setProgress(true);
                                    }
                                  }
                                }
                              : null,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SvgPicture.asset(
                                'assets/images/save_for_later.svg',
                                colorFilter: ColorFilter.mode(
                                  Theme.of(context).colorScheme.primarytheme,
                                  BlendMode.srcIn,
                                ),
                                width: 18,
                              ),
                              const SizedBox(
                                width: 10,
                              ),
                              Flexible(
                                child: Text(
                                  getTranslated(context, 'SAVEFORLATER_BTN')!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall!
                                      .copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .fontColor,
                                      ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (context.read<UserProvider>().userId != "") ...[
                      VerticalDivider(
                        color: Theme.of(context).colorScheme.simmerHigh,
                        thickness: 1,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: InkWell(
                            onTap: !buynow &&
                                    !context.read<CartProvider>().isProgress
                                ? () {
                                    setState(() {
                                      buynow = true;
                                    });
                                    isBuyNow(
                                      cartList[index]
                                                  .productList![0]
                                                  .availability ==
                                              '0'
                                          ? cartList[index]
                                              .productList![0]
                                              .prVarientList![selectedPos]
                                              .id!
                                          : cartList[index].varientId,
                                      cartList[index]
                                                  .productList![0]
                                                  .availability ==
                                              "0"
                                          ? "1"
                                          : cartList[index].qty,
                                      double.parse(
                                        cartList[index].perItemTotal!,
                                      ),
                                      cartList[index],
                                      selectedPos,
                                      selIndex: cartList[index]
                                                  .productList![0]
                                                  .availability ==
                                              '0'
                                          ? selectedPos
                                          : null,
                                    );
                                  }
                                : null,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SvgPicture.asset(
                                  'assets/images/buy_now.svg',
                                  colorFilter: ColorFilter.mode(
                                    Theme.of(context).colorScheme.primarytheme,
                                    BlendMode.srcIn,
                                  ),
                                  width: 18,
                                ),
                                const SizedBox(
                                  width: 10,
                                ),
                                Flexible(
                                  child: Text(
                                    getTranslated(context, 'BUYNOW2')!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall!
                                        .copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .fontColor,
                                        ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget cartItem(int index, List<SectionModel> cartList) {
      int selectedPos = 0;
      for (int i = 0;
          i < cartList[index].productList![0].prVarientList!.length;
          i++) {
        if (cartList[index].varientId ==
            cartList[index].productList![0].prVarientList![i].id) {
          selectedPos = i;
        }
      }
      double price = double.parse(
        cartList[index].productList![0].prVarientList![selectedPos].disPrice!,
      );
      if (price == 0) {
        price = double.parse(
          cartList[index].productList![0].prVarientList![selectedPos].price!,
        );
      }
      cartList[index].perItemPrice = price.toString();
      cartList[index].perItemTotal =
          ((cartList[index].productList![0].isSalesOn == "1"
                      ? double.parse(
                          cartList[index]
                              .productList![0]
                              .prVarientList![selectedPos]
                              .saleFinalPrice!,
                        )
                      : price) *
                  double.parse(cartList[index].qty!))
              .toString();
      _controller[index].text = cartList[index].qty!;
      List att = [];
      List val = [];
      if (cartList[index].productList![0].prVarientList![selectedPos].attr_name !=
          "") {
        att = cartList[index]
            .productList![0]
            .prVarientList![selectedPos]
            .attr_name!
            .split(',');
        val = cartList[index]
            .productList![0]
            .prVarientList![selectedPos]
            .varient_value!
            .split(',');
      }
      String? id;
      String? varId;
      bool? avail = false;
      String deliveryMsg = '';
      if (deliverableList.isNotEmpty) {
        id = cartList[index].id;
        varId = cartList[index].productList![0].prVarientList![selectedPos].id;
        for (int i = 0; i < deliverableList.length; i++) {
          if (id == deliverableList[i].prodId &&
              varId == deliverableList[i].varId) {
            avail = deliverableList[i].isDel;
            if (deliverableList[i].msg != null) {
              deliveryMsg = deliverableList[i].msg!;
            }
            break;
          }
        }
      }
      return Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              Row(
                children: <Widget>[
                  Hero(
                    tag: "$cartHero$index${cartList[index].productList![0].id}",
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7.0),
                      child: networkImageCommon(
                        cartList[index].productList![0].type ==
                                    "variable_product" &&
                                cartList[index]
                                    .productList![0]
                                    .prVarientList![selectedPos]
                                    .images!
                                    .isNotEmpty
                            ? cartList[index]
                                .productList![0]
                                .prVarientList![selectedPos]
                                .images![0]
                            : cartList[index].productList![0].image!,
                        100,
                        false,
                        height: 100,
                        width: 100,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(start: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding:
                                      const EdgeInsetsDirectional.only(top: 5.0),
                                 child: Text(
  getTranslated(context, cartList[index].productList![0].name!) 
    ?? cartList[index].productList![0].name!,
  style: Theme.of(context).textTheme.titleSmall!.copyWith(
    color: Theme.of(context).colorScheme.lightBlack,
  ),
  maxLines: 2,
  overflow: TextOverflow.ellipsis,
),

                                ),
                              ),
                              InkWell(
                                child: Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    start: 8.0,
                                    end: 8,
                                    bottom: 8,
                                  ),
                                  child: Icon(
                                    Icons.close,
                                    size: 13,
                                    color:
                                        Theme.of(context).colorScheme.fontColor,
                                  ),
                                ),
                                onTap: () {
                                  if (context.read<CartProvider>().isProgress ==
                                      false) {
                                    deleteProductFromCart(
                                      index,
                                      1,
                                      cartList,
                                      selectedPos,
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                          if (cartList[index]
                                      .productList![0]
                                      .prVarientList![selectedPos]
                                      .attr_name !=
                                  "" &&
                              cartList[index]
                                  .productList![0]
                                  .prVarientList![selectedPos]
                                  .attr_name!
                                  .isNotEmpty)
                            ListView.builder(
                              physics: const NeverScrollableScrollPhysics(),
                              shrinkWrap: true,
                              itemCount: att.length,
                              itemBuilder: (context, index) {
                                return Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        att[index].trim() + ":",
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall!
                                            .copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .lightBlack,
                                            ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsetsDirectional.only(
                                        start: 5.0,
                                      ),
                                      child: Text(
                                        val[index],
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall!
                                            .copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .lightBlack,
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            )
                          else
                            const SizedBox.shrink(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    
                                      // Original price (if discount exists) with strikethrough:
if (double.parse(cartList[index].productList![0].prVarientList![selectedPos].disPrice!) != 0)
  buildConvertedPrice(
    context,
    double.parse(cartList[index].productList![0].prVarientList![selectedPos].price!),
    isOriginal: true,
  )
else
  const SizedBox.shrink(),

// Final (or sale) price:
buildConvertedPrice(
  context,
  cartList[index].productList![0].isSalesOn == "1"
      ? double.parse(cartList[index].productList![0].prVarientList![selectedPos].saleFinalPrice!)
      : price,
)

                                  ],
                                ),
                              ),
                              if (cartList[index].productList![0].availability ==
                                      "1" ||
                                  cartList[index].productList![0].stockType == "")
                                Row(
                                  children: <Widget>[
                                    Row(
                                      children: <Widget>[
                                        InkWell(
                                          child: Card(
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(50),
                                            ),
                                            child: const Padding(
                                              padding: EdgeInsets.all(8.0),
                                              child: Icon(
                                                Icons.remove,
                                                size: 15,
                                              ),
                                            ),
                                          ),
                                          onTap: () {
                                            if (context
                                                    .read<CartProvider>()
                                                    .isProgress ==
                                                false) {
                                              _optimisticQtyChange(
                                                index,
                                                -int.parse(
                                                  cartList[index]
                                                      .productList![0]
                                                      .qtyStepSize!,
                                                ),
                                                cartList,
                                              );
                                            }
                                          },
                                        ),
                                        SizedBox(
                                          width: 37,
                                          height: 20,
                                          child: Stack(
                                            children: [
                                              Center(
                                                child: Text(
                                                  cartList[index].qty!,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .fontColor,
                                                  ),
                                                ),
                                              ),
                                              PopupMenuButton<String>(
                                                tooltip: '',
                                                icon: const Icon(
                                                  Icons.arrow_drop_down,
                                                  size: 1,
                                                ),
                                                onSelected: (String value) {
                                                  final delta = int.parse(value) -
                                                      int.parse(cartList[index].qty!);
                                                  if (delta != 0) {
                                                    _optimisticQtyChange(
                                                      index,
                                                      delta,
                                                      cartList,
                                                    );
                                                  }
                                                },
                                                itemBuilder:
                                                    (BuildContext context) {
                                                  return cartList[index]
                                                      .productList![0]
                                                      .itemsCounter!
                                                      .map<PopupMenuItem<String>>(
                                                          (String value) {
                                                    return PopupMenuItem(
                                                      value: value,
                                                      child: Text(
                                                        value,
                                                        style: TextStyle(
                                                          color: Theme.of(
                                                            context,
                                                          ).colorScheme.fontColor,
                                                        ),
                                                      ),
                                                    );
                                                  }).toList();
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                        InkWell(
                                          child: Card(
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(50),
                                            ),
                                            child: const Padding(
                                              padding: EdgeInsets.all(8.0),
                                              child: Icon(
                                                Icons.add,
                                                size: 15,
                                              ),
                                            ),
                                          ),
                                          onTap: () {
                                            if (context
                                                    .read<CartProvider>()
                                                    .isProgress ==
                                                false) {
                                              _optimisticQtyChange(
                                                index,
                                                int.parse(
                                                  cartList[index]
                                                      .productList![0]
                                                      .qtyStepSize!,
                                                ),
                                                cartList,
                                              );
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                )
                              else
                                const SizedBox.shrink(),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    getTranslated(context, 'NET_AMOUNT')!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.lightBlack2,
                    ),
                  ),
                  // For the net amount with quantity (as a row)
Row(
  children: [
    buildConvertedPrice(
      context,
      double.parse(cartList[index].netAmt!),
    ),
    Text(
      " x ${cartList[index].qty}",
      style: TextStyle(
        color: Theme.of(context).colorScheme.lightBlack2,
      ),
    ),
  ],
),

// For the total (net amount multiplied by quantity)
buildConvertedPrice(
  context,
  double.parse(cartList[index].netAmt!) * int.parse(cartList[index].qty!),
),

                  
                ],
              ),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    getTranslated(context, 'TOTAL_LBL')!,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.lightBlack2,
                    ),
                  ),
                  buildConvertedPrice(
  context,
  double.parse(cartList[index].perItemTotal!),
),

                ],
              ),
              if (cartList[index].productList![0].productType !=
                  'digital_product')
                if (IS_LOCAL_PICKUP != "1" || isStorePickUp != "true")
                  !avail! && deliverableList.isNotEmpty
                      ? Text(
                          deliveryMsg != ''
                              ? deliveryMsg
                              : getTranslated(context, 'NOT_DEL')!,
                          overflow: TextOverflow.ellipsis,
                          softWrap: true,
                          maxLines: 2,
                          style: Theme.of(context).textTheme.titleSmall!.copyWith(
                                color: colors.red,
                              ),
                        )
                      : const SizedBox.shrink(),
            ],
          ),
        ),
      );
    }

    Widget saveLaterItem(int index) {
      int selectedPos = 0;
      for (int i = 0;
          i < saveLaterList[index].productList![0].prVarientList!.length;
          i++) {
        if (saveLaterList[index].varientId ==
            saveLaterList[index].productList![0].prVarientList![i].id) {
          selectedPos = i;
        }
      }
      double price = double.parse(
        saveLaterList[index]
            .productList![0]
            .prVarientList![selectedPos]
            .disPrice!,
      );
      if (price == 0) {
        price = double.parse(
          saveLaterList[index].productList![0].prVarientList![selectedPos].price!,
        );
      }
      double off = double.parse(
                saveLaterList[index]
                    .productList![0]
                    .prVarientList![selectedPos]
                    .price!,
              ) -
              double.parse(
                saveLaterList[index]
                    .productList![0]
                    .prVarientList![selectedPos]
                    .disPrice!,
              )
          ;
      off = off *
          100 /
          double.parse(
            saveLaterList[index]
                .productList![0]
                .prVarientList![selectedPos]
                .price!,
          );
      saveLaterList[index].perItemPrice = price.toString();
      if (saveLaterList[index].productList![0].availability != "0") {
        saveLaterList[index].perItemTotal =
            ((saveLaterList[index].productList![0].isSalesOn == "1"
                        ? double.parse(
                            saveLaterList[index]
                                .productList![0]
                                .prVarientList![selectedPos]
                                .saleFinalPrice!,
                          )
                        : price) *
                    double.parse(saveLaterList[index].qty!))
                .toString();
      }
      return Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 1.0,
        ),
        child: Card(
          elevation: 0.1,
          child: Column(
            children: [
              InkWell(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Hero(
                      tag:
                          "$cartHero$index${saveLaterList[index].productList![0].id}",
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(7.0),
                              child: Stack(
                                children: [
                                  networkImageCommon(
                                    saveLaterList[index].productList![0].type ==
                                                "variable_product" &&
                                            saveLaterList[index]
                                                .productList![0]
                                                .prVarientList![selectedPos]
                                                .images!
                                                .isNotEmpty
                                        ? saveLaterList[index]
                                            .productList![0]
                                            .prVarientList![selectedPos]
                                            .images![0]
                                        : saveLaterList[index]
                                            .productList![0]
                                            .image!,
                                    100,
                                    false,
                                    height: 100,
                                    width: 100,
                                  ),
                                  Positioned.fill(
                                    child: saveLaterList[index]
                                                .productList![0]
                                                .availability ==
                                            "0"
                                        ? Container(
                                            height: 55,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .white70,
                                            padding: const EdgeInsets.all(2),
                                            child: Center(
                                              child: Text(
                                                getTranslated(
                                                  context,
                                                  'OUT_OF_STOCK_LBL',
                                                )!,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall!
                                                    .copyWith(
                                                      color: Colors.red,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ],
                              ),
                            ),
                            if (off != 0 &&
                                saveLaterList[index]
                                        .productList![0]
                                        .prVarientList![selectedPos]
                                        .disPrice! !=
                                    "0")
                              saveLaterList[index].productList![0].isSalesOn ==
                                      "1"
                                  ? getDiscountLabel(
                                      double.parse(
                                        saveLaterList[index]
                                            .productList![0]
                                            .prVarientList![selectedPos]
                                            .saleFinalPrice!,
                                      ).toStringAsFixed(2),
                                    )
                                  : getDiscountLabel(off.toStringAsFixed(2))
                            else
                              const SizedBox.shrink(),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsetsDirectional.all(
                          8.0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                      top: 5.0,
                                    ),
                                    child: Text(
  getTranslated(context, saveLaterList[index].productList![0].name!) 
    ?? saveLaterList[index].productList![0].name!,
  style: Theme.of(context).textTheme.titleMedium!.copyWith(
    color: Theme.of(context).colorScheme.fontColor,
  ),
  maxLines: 2,
  overflow: TextOverflow.ellipsis,
),

                                  ),
                                ),
                                InkWell(
                                  child: Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                      start: 8.0,
                                      end: 8,
                                      bottom: 8,
                                    ),
                                    child: Icon(
                                      Icons.close,
                                      size: 20,
                                      color:
                                          Theme.of(context).colorScheme.fontColor,
                                    ),
                                  ),
                                  onTap: () async {
                                    if (context.read<CartProvider>().isProgress ==
                                        false) {
                                      if (context.read<UserProvider>().userId !=
                                          "") {
                                        deleteProductFromCart(
                                          index,
                                          2,
                                          saveLaterList,
                                          selectedPos,
                                        );
                                      } else {
                                        db.removeSaveForLater(
                                          saveLaterList[index]
                                              .productList![0]
                                              .prVarientList![selectedPos]
                                              .id!,
                                          saveLaterList[index]
                                              .productList![0]
                                              .id!,
                                        );
                                        proVarIds.remove(
                                          saveLaterList[index]
                                              .productList![0]
                                              .prVarientList![selectedPos]
                                              .id,
                                        );
                                        saveLaterList.removeAt(index);
                                        setState(() {});
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                            Row(
  children: <Widget>[
    // If there's a discount, show the original price (converted) with strikethrough.
    if (double.parse(
            saveLaterList[index]
                .productList![0]
                .prVarientList![selectedPos]
                .disPrice!,
          ) !=
          0)
      buildConvertedPrice(
        context,
        double.parse(
          saveLaterList[index]
              .productList![0]
              .prVarientList![selectedPos]
              .price!,
        ),
        isOriginal: true,
      ),
    // Then show the final price (converted).
    buildConvertedPrice(
      context,
      saveLaterList[index].productList![0].isSalesOn == "1"
          ? double.parse(
              saveLaterList[index]
                  .productList![0]
                  .prVarientList![selectedPos]
                  .saleFinalPrice!,
            )
          : price,
    ),
  ],
),

                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                onTap: () {
                  Navigator.pushNamed(
                    context,
                    Routers.productDetails,
                    arguments: {
                      "secPos": 0,
                      "index": index,
                      "list": true,
                      "id": saveLaterList[index].productList![0].id,
                    },
                  );
                },
              ),
              if (saveLaterList[index].productList![0].availability == "1" ||
                  saveLaterList[index].productList![0].stockType == "")
                Column(
                  children: [
                    Divider(
                      color: Theme.of(context).colorScheme.simmerHigh,
                      thickness: 1,
                      height: 0,
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: InkWell(
                        onTap: !addCart &&
                                !context.read<CartProvider>().isProgress
                            ? () {
                                if (context.read<UserProvider>().userId != "") {
                                  setState(() {
                                    addCart = true;
                                  });
                                  saveForLater(
                                    saveLaterList[index]
                                        .productList![0]
                                        .prVarientList![selectedPos]
                                        .id,
                                    "2",
                                    saveLaterList[index].qty,
                                    double.parse(
                                      saveLaterList[index].perItemTotal!,
                                    ),
                                    saveLaterList[index],
                                    true,
                                    selectedPos,
                                  );
                                } else {
                                  setState(() async {
                                    addCart = true;
                                    context
                                        .read<CartProvider>()
                                        .setProgress(true);
                                    await cartFun(
                                      index: index,
                                      selectedPos: selectedPos,
                                      total: double.parse(
                                        saveLaterList[index].perItemTotal!,
                                      ),
                                    );
                                  });
                                }
                              }
                            : null,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SvgPicture.asset(
                              'assets/images/add_to_cart.svg',
                              colorFilter: ColorFilter.mode(
                                Theme.of(context).colorScheme.primarytheme,
                                BlendMode.srcIn,
                              ),
                              width: 18,
                            ),
                            const SizedBox(
                              width: 10,
                            ),
                            Text(
                              getTranslated(context, 'ADD_CART2')!,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall!
                                  .copyWith(
                                    color:
                                        Theme.of(context).colorScheme.fontColor,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              else
                const SizedBox.shrink(),
            ],
          ),
        ),
      );
    }

    Future<void> _getCart(String save) async {
    _isNetworkAvailable = await isNetworkAvailable();
    if (_isNetworkAvailable) {
      try {
        // Log before calling the API.
        print("Before API call: user_id: ${context.read<UserProvider>().userId}, SAVE_LATER: $save, only_delivery_charge: 0");
        
        final parameter = {
          USER_ID: context.read<UserProvider>().userId,
          SAVE_LATER: save,
          "only_delivery_charge": "0",
        };
        apiBaseHelper.postAPICall(getCartApi, parameter).then(
          (getdata) {
            final bool error = getdata["error"];
            final String? msg = getdata["message"];
            if (!error) {
              final data = getdata["data"];
              
              // Log the raw product variant ids from API response.
              if (data is List) {
                for (var item in data) {
                  print("Raw cart item - product_variant_id: ${item[PRODUCT_VARIENT_ID]}");
                }
              }
              
              if ((data as List).isEmpty) {
                context.read<CartProvider>().setCartlist([]);
                context.read<UserProvider>().setCartCount("0");
                _isCartLoad = false;
                setState(() {});
                return;
              }
              
              originalPrice = double.parse(getdata[SUB_TOTAL]);
              taxPersontage = double.parse(getdata[TAX_PER]);
              totalPrice = originalPrice;
              
              // Map raw data to SectionModel objects.
              final List<SectionModel> cartList =
                  data.map((data) => SectionModel.fromCart(data)).toList();
              
              // Log each cart item's product variant id after mapping.
              for (int i = 0; i < cartList.length; i++) {
                print("Mapped cart item - product_variant_id: ${cartList[i].varientId}, qty: ${cartList[i].qty}, product_id: ${cartList[i].productId}");
              }
              
              // Address check for non-digital products.
              if (cartList[0].productList![0].productType != 'digital_product') {
                _getAddress(
                  context,
                  onComplete: () {
                    setState(() {
                      _isLoading = false;
                    });
                    checkoutState?.call(() {});
                  },
                  onInternetState: (hasInternet) {
                    _isNetworkAvailable = hasInternet;
                    setState(() {});
                  },
                );
              } else {
                setState(() {
                  _isLoading = false;
                });
              }
              
              context.read<CartProvider>().setCartlist(cartList);
              context.read<UserProvider>().setCartCount(cartList.length.toString());
              if (getdata.containsKey(PROMO_CODES)) {
                final promo = getdata[PROMO_CODES];
                promoList = (promo as List).map((e) => Promo.fromJson(e)).toList();
              }
              for (int i = 0; i < cartList.length; i++) {
                _controller.add(TextEditingController());
              }
            } else {
              if (msg != 'Cart Is Empty !') setSnackbar(msg!, context);
            }
            if (mounted) {
              setState(() {
                _isCartLoad = false;
              });
              if (widget.buyNow) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  checkout().then((_) {
                    if (mounted) Navigator.pop(context);
                  });
                });
              }
            }
          },
          onError: (error) {
            setSnackbar(error.toString(), context);
          },
        );
      } on TimeoutException catch (_) {
        setSnackbar(getTranslated(context, 'somethingMSg')!, context);
      }
    } else {
      if (mounted) {
        setState(() {
          _isNetworkAvailable = false;
        });
      }
    }
  }


    Future<void> _getOfflineCart() async {
      if (productIds.isNotEmpty) {
        _isNetworkAvailable = await isNetworkAvailable();
        if (_isNetworkAvailable) {
          try {
            final parameter = {"product_variant_ids": productIds.join(',')};
            apiBaseHelper.postAPICall(getProductApi, parameter).then(
              (getdata) async {
                final bool error = getdata["error"];
                if (!error) {
                  final data = getdata["data"];
                  setState(() {
                    context.read<CartProvider>().setCartlist([]);
                    originalPrice = 0;
                  });
                  final List<Product> cartList = (data as List)
                      .map((data) => Product.fromJson(data))
                      .toList();
                  for (int i = 0; i < cartList.length; i++) {
                    for (int j = 0; j < cartList[i].prVarientList!.length; j++) {
                      if (productIds.contains(cartList[i].prVarientList![j].id)) {
                        final String qty = (await db.checkCartItemExists(
                          cartList[i].id!,
                          cartList[i].prVarientList![j].id!,
                        ))!;
                        final List<Product> prList = [];
                        cartList[i].prVarientList![j].cartCount = qty;
                        prList.add(cartList[i]);
                        context.read<CartProvider>().addCartItem(
                              SectionModel(
                                id: cartList[i].id,
                                varientId: cartList[i].prVarientList![j].id,
                                qty: qty,
                                productList: prList,
                              ),
                            );
                        double price =
                            double.parse(cartList[i].prVarientList![j].disPrice!);
                        if (price == 0) {
                          price =
                              double.parse(cartList[i].prVarientList![j].price!);
                        }
                        final double total = price * int.parse(qty);
                        setState(() {
                          originalPrice = originalPrice + total;
                        });
                      }
                    }
                  }
                  setState(() {});
                }
                if (mounted) {
                  setState(() {
                    _isCartLoad = false;
                  });
                  if (widget.buyNow) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      checkout().then((_) {
                        if (mounted) Navigator.pop(context);
                      });
                    });
                  }
                }
              },
              onError: (error) {
                setSnackbar(error.toString(), context);
              },
            );
          } on TimeoutException catch (_) {
            setSnackbar(getTranslated(context, 'somethingMSg')!, context);
          }
        } else {
          if (mounted) {
            setState(() {
              _isNetworkAvailable = false;
            });
          }
        }
      } else {
        context.read<CartProvider>().setCartlist([]);
        setState(() {
          _isCartLoad = false;
        });
        if (widget.buyNow) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            checkout().then((_) {
              if (mounted) Navigator.pop(context);
            });
          });
        }
      }
    }

    Future<void> _getOffSaveLater() async {
      if (proVarIds.isNotEmpty) {
        _isNetworkAvailable = await isNetworkAvailable();
        if (_isNetworkAvailable) {
          try {
            final parameter = {"product_variant_ids": proVarIds.join(',')};
            apiBaseHelper.postAPICall(getProductApi, parameter).then(
              (getdata) async {
                final bool error = getdata["error"];
                if (!error) {
                  final data = getdata["data"];
                  saveLaterList.clear();
                  final List<Product> cartList = (data as List)
                      .map((data) => Product.fromJson(data))
                      .toList();
                  for (int i = 0; i < cartList.length; i++) {
                    for (int j = 0; j < cartList[i].prVarientList!.length; j++) {
                      if (proVarIds.contains(cartList[i].prVarientList![j].id)) {
                        final String qty = (await db.checkSaveForLaterExists(
                          cartList[i].id!,
                          cartList[i].prVarientList![j].id!,
                        ))!;
                        final List<Product> prList = [];
                        prList.add(cartList[i]);
                        saveLaterList.add(
                          SectionModel(
                            id: cartList[i].id,
                            varientId: cartList[i].prVarientList![j].id,
                            qty: qty,
                            productList: prList,
                          ),
                        );
                      }
                    }
                  }
                  setState(() {});
                }
                if (mounted) {
                  setState(() {
                    _isSaveLoad = false;
                  });
                }
              },
              onError: (error) {
                setSnackbar(error.toString(), context);
              },
            );
          } on TimeoutException catch (_) {
            setSnackbar(getTranslated(context, 'somethingMSg')!, context);
          }
        } else {
          if (mounted) {
            setState(() {
              _isNetworkAvailable = false;
            });
          }
        }
      } else {
        setState(() {
          _isSaveLoad = false;
        });
        saveLaterList = [];
      }
    }

    Future<void> _getSaveLater(String save) async {
      _isNetworkAvailable = await isNetworkAvailable();
      if (_isNetworkAvailable) {
        try {
          final parameter = {
            USER_ID: context.read<UserProvider>().userId,
            SAVE_LATER: save,
            "only_delivery_charge": "0",
          };
          apiBaseHelper.postAPICall(getCartApi, parameter).then(
            (getdata) {
              final bool error = getdata["error"];
              final String? msg = getdata["message"];
              if (!error) {
                final data = getdata["data"];
                saveLaterList = (data as List)
                    .map((data) => SectionModel.fromCart(data))
                    .toList();
                final List<SectionModel> cartList =
                    context.read<CartProvider>().cartList;
                for (int i = 0; i < cartList.length; i++) {
                  _controller.add(TextEditingController());
                }
              } else {
                if (msg != 'Cart Is Empty !') setSnackbar(msg!, context);
              }
              if (mounted) setState(() {});
            },
            onError: (error) {
              setSnackbar(error.toString(), context);
            },
          );
        } on TimeoutException catch (_) {
          setSnackbar(getTranslated(context, 'somethingMSg')!, context);
        }
      } else {
        if (mounted) {
          setState(() {
            _isNetworkAvailable = false;
          });
        }
      }
      return;
    }

    Future<void> addToCart(
      int index,
      String qty,
      List<SectionModel> cartList,
    ) async {
      _isNetworkAvailable = await isNetworkAvailable();
      if (_isNetworkAvailable) {
        try {
          context.read<CartProvider>().setProgress(true);
          if (int.parse(qty) < cartList[index].productList![0].minOrderQuntity!) {
            qty = cartList[index].productList![0].minOrderQuntity.toString();
            setSnackbar("${getTranslated(context, 'MIN_MSG')}$qty", context);
          }
          final parameter = {
            PRODUCT_VARIENT_ID: cartList[index].varientId,
            USER_ID: context.read<UserProvider>().userId,
            QTY: qty,
          };
          apiBaseHelper.postAPICall(manageCartApi, parameter).then(
            (getdata) {
              final bool error = getdata["error"];
              final String? msg = getdata["message"];
              if (!error) {
                final data = getdata["data"];
                final String qty = data['total_quantity'];
                context.read<UserProvider>().setCartCount(data['cart_count']);
                cartList[index].qty = qty;
                originalPrice = double.parse(data['sub_total']);
                _controller[index].text = qty;
                totalPrice = 0;
                final cart = getdata["cart"];
                final List<SectionModel> uptcartList = (cart as List)
                    .map((cart) => SectionModel.fromCart(cart))
                    .toList();
                context.read<CartProvider>().setCartlist(uptcartList);
                if (IS_SHIPROCKET_ON == "0") {
                  if (!ISFLAT_DEL) {
                    if (addressList.isEmpty) {
                      deliveryCharge = 0;
                    } else {
                      if (originalPrice <
                          double.parse(addressList[selectedAddress!].freeAmt!)) {
                        deliveryCharge = double.parse(
                          addressList[selectedAddress!].deliveryCharge!,
                        );
                      } else {
                        deliveryCharge = 0;
                      }
                    }
                  } else {
                    if (originalPrice < double.parse(MIN_AMT!)) {
                      deliveryCharge = double.parse(CUR_DEL_CHR!);
                    } else {
                      deliveryCharge = 0;
                    }
                  }
                }
                totalPrice = originalPrice;
                if (isPromoValid!) {
                  validatePromo(false);
                } else if (isUseWallet!) {
                  context.read<CartProvider>().setProgress(false);
                  if (mounted) {
                    setState(() {
                      remWalBal = 0;
                      paymentMethod = null;
                      usedBalance = 0;
                      isUseWallet = false;
                      isPayLayShow = true;
                      selectedMethod = null;
                    });
                  }
                } else {
                  setState(() {});
                  context.read<CartProvider>().setProgress(false);
                }
              } else {
                setSnackbar(msg!, context);
                context.read<CartProvider>().setProgress(false);
              }
            },
            onError: (error) {
              setSnackbar(error.toString(), context);
            },
          );
        } on TimeoutException catch (_) {
          setSnackbar(getTranslated(context, 'somethingMSg')!, context);
          context.read<CartProvider>().setProgress(false);
        }
      } else {
        if (mounted) {
          setState(() {
            _isNetworkAvailable = false;
          });
        }
      }
    }

    Future<void> addToCartCheckout(
      int index,
      String qty,
      List<SectionModel> cartList,
    ) async {
      _isNetworkAvailable = await isNetworkAvailable();
      if (_isNetworkAvailable) {
        try {
          context.read<CartProvider>().setProgress(true);
          if (int.parse(qty) < cartList[index].productList![0].minOrderQuntity!) {
            qty = cartList[index].productList![0].minOrderQuntity.toString();
            setSnackbar("${getTranslated(context, 'MIN_MSG')}$qty", context);
          }
          final parameter = {
            PRODUCT_VARIENT_ID: cartList[index].varientId,
            USER_ID: context.read<UserProvider>().userId,
            QTY: qty,
          };
          apiBaseHelper.postAPICall(manageCartApi, parameter).then(
            (getdata) {
              final bool error = getdata["error"];
              final String? msg = getdata["message"];
              if (!error) {
                final data = getdata["data"];
                final String qty = data['total_quantity'];
                context.read<UserProvider>().setCartCount(data['cart_count']);
                cartList[index].qty = qty;
                originalPrice = double.parse(data['sub_total']);
                _controller[index].text = qty;
                totalPrice = 0;
                if (IS_SHIPROCKET_ON == "0") {
                  if (!ISFLAT_DEL) {
                    if (originalPrice <
                        double.parse(addressList[selectedAddress!].freeAmt!)) {
                      deliveryCharge = double.parse(
                        addressList[selectedAddress!].deliveryCharge!,
                      );
                    } else {
                      deliveryCharge = 0;
                    }
                  } else {
                    if (originalPrice < double.parse(MIN_AMT!)) {
                      deliveryCharge = double.parse(CUR_DEL_CHR!);
                      print("deliverycharge--->$deliveryCharge");
                    } else {
                      deliveryCharge = 0;
                    }
                  }
                }
                totalPrice = originalPrice;
                if (isPromoValid!) {
                  validatePromo(true);
                } else if (isUseWallet!) {
                  if (mounted) {
                    checkoutState?.call(() {
                      remWalBal = 0;
                      paymentMethod = null;
                      usedBalance = 0;
                      isUseWallet = false;
                      isPayLayShow = true;
                      selectedMethod = null;
                    });
                  }
                  setState(() {});
                } else {
                  context.read<CartProvider>().setProgress(false);
                  setState(() {});
                  checkoutState?.call(() {});
                }
              } else {
                setSnackbar(msg!, context);
                context.read<CartProvider>().setProgress(false);
              }
            },
            onError: (error) {
              setSnackbar(error.toString(), context);
            },
          );
        } on TimeoutException catch (_) {
          setSnackbar(getTranslated(context, 'somethingMSg')!, context);
          context.read<CartProvider>().setProgress(false);
        }
      } else {
        if (mounted) {
          checkoutState?.call(() {
            _isNetworkAvailable = false;
          });
        }
        setState(() {});
      }
    }

    saveForLaterFun(
      int index,
      int selectedPos,
      double total,
      List<SectionModel> cartList,
    ) async {
      db.moveToCartOrSaveLater(
        "cart",
        cartList[index].productList![0].prVarientList![selectedPos].id!,
        cartList[index].id!,
        cartList[index].productList![0].productType!,
        context,
      );
      proVarIds
          .add(cartList[index].productList![0].prVarientList![selectedPos].id!);
      productIds.remove(
        cartList[index].productList![0].prVarientList![selectedPos].id,
      );
      originalPrice = originalPrice - total;
      saveLaterList.add(context.read<CartProvider>().cartList[index]);
      context.read<CartProvider>().removeCartItem(
            cartList[index].productList![0].prVarientList![selectedPos].id!,
          );
      saveLater = false;
      context.read<CartProvider>().setProgress(false);
      setState(() {});
    }

    Future<void> cartFun({
      required int index,
      required int selectedPos,
      required double total,
    }) async {
      db.moveToCartOrSaveLater(
        'save',
        saveLaterList[index].productList![0].prVarientList![selectedPos].id!,
        saveLaterList[index].id!,
        saveLaterList[index].productList![0].productType!,
        context,
      );
      productIds.add(
        saveLaterList[index].productList![0].prVarientList![selectedPos].id!,
      );
      proVarIds.remove(
        saveLaterList[index].productList![0].prVarientList![selectedPos].id,
      );
      originalPrice = originalPrice + total;
      context.read<CartProvider>().addCartItem(saveLaterList[index]);
      saveLaterList.removeAt(index);
      addCart = false;
      context.read<CartProvider>().setProgress(false);
      setState(() {});
    }

    saveForLater(
      String? id,
      String save,
      String? qty,
      double price,
      SectionModel curItem,
      bool fromSave,
      int selectedPos, {
      int? selIndex,
    }) async {
      _isNetworkAvailable = await isNetworkAvailable();
      if (_isNetworkAvailable) {
        try {
          context.read<CartProvider>().setProgress(true);
          final parameter = {
            PRODUCT_VARIENT_ID: id,
            USER_ID: context.read<UserProvider>().userId,
            QTY: qty,
            SAVE_LATER: save,
          };
          apiBaseHelper.postAPICall(manageCartApi, parameter).then(
            (getdata) {
              final bool error = getdata["error"];
              final String? msg = getdata["message"];
              if (!error) {
                final data = getdata["data"];
                context.read<UserProvider>().setCartCount(data['cart_count']);
                if (save == "1") {
                  saveLaterList.add(curItem);
                  context
                      .read<CartProvider>()
                      .removeCartItem(id!, index: selIndex);
                  setState(() {
                    saveLater = false;
                  });
                  originalPrice = originalPrice - price;
                } else {
                  final List<SectionModel> cartList =
                      context.read<CartProvider>().cartList;
                  if (cartList.isNotEmpty) {
                    final SectionModel? tempId = cartList.firstWhereOrNull(
                      (cp) => cp.id == curItem.id && cp.varientId == id,
                    );
                    if (tempId != null) {
                      context.read<CartProvider>().updateCartItem(
                            curItem.id,
                            (int.parse(tempId.qty!) + int.parse(qty.toString()))
                                .toString(),
                            selectedPos,
                            id!,
                          );
                      saveLaterList.removeWhere((item) => item.varientId == id);
                    } else {
                      context.read<CartProvider>().addCartItem(curItem);
                      saveLaterList.removeWhere((item) => item.varientId == id);
                    }
                  } else {
                    context.read<CartProvider>().addCartItem(curItem);
                    saveLaterList.removeWhere((item) => item.varientId == id);
                  }
                  setState(() {
                    addCart = false;
                  });
                  originalPrice = originalPrice + price;
                }
                totalPrice = 0;
                if (IS_SHIPROCKET_ON == "0") {
                  if (!ISFLAT_DEL) {
                    if (addressList.isNotEmpty &&
                        originalPrice <
                            double.parse(
                                addressList[selectedAddress!].freeAmt!,)) {
                      deliveryCharge = double.parse(
                        addressList[selectedAddress!].deliveryCharge!,
                      );
                    } else {
                      deliveryCharge = 0;
                    }
                  } else {
                    if (originalPrice < double.parse(MIN_AMT!)) {
                      deliveryCharge = double.parse(CUR_DEL_CHR!);
                    } else {
                      deliveryCharge = 0;
                    }
                  }
                }
                totalPrice = originalPrice;
                if (isPromoValid!) {
                  validatePromo(false);
                } else if (isUseWallet!) {
                  context.read<CartProvider>().setProgress(false);
                  if (mounted) {
                    setState(() {
                      remWalBal = 0;
                      paymentMethod = null;
                      usedBalance = 0;
                      isUseWallet = false;
                      isPayLayShow = true;
                    });
                  }
                } else {
                  context.read<CartProvider>().setProgress(false);
                  setState(() {});
                }
              } else {
                setSnackbar(msg!, context);
              }
              context.read<CartProvider>().setProgress(false);
            },
            onError: (error) {
              setSnackbar(error.toString(), context);
            },
          );
        } on TimeoutException catch (_) {
          setSnackbar(getTranslated(context, 'somethingMSg')!, context);
          context.read<CartProvider>().setProgress(false);
        }
      } else {
        if (mounted) {
          setState(() {
            _isNetworkAvailable = false;
          });
        }
      }
    }

    isBuyNow(
      String? id,
      String? qty,
      double price,
      SectionModel curItem,
      int selectedPos, {
      int? selIndex,
    }) async {
      _isNetworkAvailable = await isNetworkAvailable();
      if (_isNetworkAvailable) {
        try {
          context.read<CartProvider>().setProgress(true);
          final parameter = {
            PRODUCT_VARIENT_ID: id,
            USER_ID: context.read<UserProvider>().userId,
            QTY: qty,
            IS_BUY_NOW: '1',
          };
          apiBaseHelper.postAPICall(manageCartApi, parameter).then(
            (getdata) {
              final bool error = getdata["error"];
              final String? msg = getdata["message"];
              if (!error) {
                final data = getdata["data"];
                context.read<UserProvider>().setCartCount(data['cart_count']);
                originalPrice = price;
                for (final item in context.read<CartProvider>().cartList) {
                  if (item.varientId != id) {
                    saveLaterList.add(item);
                  }
                }
                context.read<CartProvider>().clearCartExcept(curItem);
                totalPrice = 0;
                if (IS_SHIPROCKET_ON == "0") {
                  if (!ISFLAT_DEL) {
                    if (addressList.isNotEmpty &&
                        originalPrice <
                            double.parse(
                                addressList[selectedAddress!].freeAmt!,)) {
                      deliveryCharge = double.parse(
                        addressList[selectedAddress!].deliveryCharge!,
                      );
                    } else {
                      deliveryCharge = 0;
                    }
                  } else {
                    if (originalPrice < double.parse(MIN_AMT!)) {
                      deliveryCharge = double.parse(CUR_DEL_CHR!);
                    } else {
                      deliveryCharge = 0;
                    }
                  }
                }
                totalPrice = originalPrice;
                if (isPromoValid!) {
                  validatePromo(false);
                } else if (isUseWallet!) {
                  context.read<CartProvider>().setProgress(false);
                  if (mounted) {
                    setState(() {
                      remWalBal = 0;
                      paymentMethod = null;
                      usedBalance = 0;
                      isUseWallet = false;
                      isPayLayShow = true;
                    });
                  }
                } else {
                  context.read<CartProvider>().setProgress(false);
                  setState(() {});
                }
                setState(() {
                  buynow = false;
                });
              } else {
                setSnackbar(msg!, context);
              }
              context.read<CartProvider>().setProgress(false);
            },
            onError: (error) {
              setSnackbar(error.toString(), context);
            },
          );
        } on TimeoutException catch (_) {
          setSnackbar(getTranslated(context, 'somethingMSg')!, context);
          context.read<CartProvider>().setProgress(false);
        }
      } else {
        if (mounted) {
          setState(() {
            _isNetworkAvailable = false;
          });
        }
      }
    }

    removeFromCartCheckout(
      int index,
      bool remove,
      List<SectionModel> cartList,
    ) async {
      _isNetworkAvailable = await isNetworkAvailable();
      if (!remove &&
          int.parse(cartList[index].qty!) ==
              cartList[index].productList![0].minOrderQuntity) {
        setSnackbar(
          "${getTranslated(context, 'MIN_MSG')}${cartList[index].qty}",
          context,
        );
      } else {
        if (_isNetworkAvailable) {
          try {
            context.read<CartProvider>().setProgress(true);
            int? qty;
            if (remove) {
              qty = 0;
            } else {
              qty = int.parse(cartList[index].qty!) -
                  int.parse(cartList[index].productList![0].qtyStepSize!);
              if (qty < cartList[index].productList![0].minOrderQuntity!) {
                qty = cartList[index].productList![0].minOrderQuntity;
                setSnackbar("${getTranslated(context, 'MIN_MSG')}$qty", context);
              }
            }
            final parameter = {
              PRODUCT_VARIENT_ID: cartList[index].varientId,
              USER_ID: context.read<UserProvider>().userId,
              QTY: qty.toString(),
            };
            apiBaseHelper.postAPICall(manageCartApi, parameter).then(
              (getdata) {
                final bool error = getdata["error"];
                final String? msg = getdata["message"];
                if (!error) {
                  final data = getdata["data"];
                  final String? qty = data['total_quantity'];
                  context.read<UserProvider>().setCartCount(data['cart_count']);
                  if (qty == "0") remove = true;
                  if (remove) {
                    context
                        .read<CartProvider>()
                        .removeCartItem(cartList[index].varientId!);
                  } else {
                    cartList[index].qty = qty.toString();
                  }
                  originalPrice = double.parse(data[SUB_TOTAL]);
                  if (IS_SHIPROCKET_ON == "0") {
                    if (!ISFLAT_DEL) {
                      if (originalPrice <
                          double.parse(addressList[selectedAddress!].freeAmt!)) {
                        deliveryCharge = double.parse(
                          addressList[selectedAddress!].deliveryCharge!,
                        );
                      } else {
                        deliveryCharge = 0;
                      }
                    } else {
                      if (originalPrice < double.parse(MIN_AMT!)) {
                        deliveryCharge = double.parse(CUR_DEL_CHR!);
                      } else {
                        deliveryCharge = 0;
                      }
                    }
                  }
                  totalPrice = 0;
                  totalPrice = originalPrice;
                  if (isPromoValid!) {
                    validatePromo(true);
                  } else if (isUseWallet!) {
                    if (mounted) {
                      checkoutState?.call(() {
                        remWalBal = 0;
                        paymentMethod = null;
                        usedBalance = 0;
                        isPayLayShow = true;
                        isUseWallet = false;
                      });
                    }
                    context.read<CartProvider>().setProgress(false);
                    setState(() {});
                  } else {
                    context.read<CartProvider>().setProgress(false);
                    checkoutState?.call(() {});
                    setState(() {});
                  }
                } else {
                  setSnackbar(msg!, context);
                  context.read<CartProvider>().setProgress(false);
                }
              },
              onError: (error) {
                setSnackbar(error.toString(), context);
              },
            );
          } on TimeoutException catch (_) {
            setSnackbar(getTranslated(context, 'somethingMSg')!, context);
            context.read<CartProvider>().setProgress(false);
            checkoutState?.call(() {});
          }
        } else {
          if (mounted) {
            checkoutState?.call(() {
              _isNetworkAvailable = false;
            });
          }
          setState(() {});
        }
      }
    }

    deleteProductFromCart(
      int index,
      int from,
      List<SectionModel> cartList,
      int selPos,
    ) async {
      _isNetworkAvailable = await isNetworkAvailable();
      if (_isNetworkAvailable) {
        try {
          context.read<CartProvider>().setProgress(true);
          String varId;
          if (cartList[index].productList![0].availability == "0") {
            varId = cartList[index].productList![0].prVarientList![selPos].id!;
          } else {
            varId = cartList[index].varientId!;
          }
          final parameter = {
            PRODUCT_VARIENT_ID: varId,
            USER_ID: context.read<UserProvider>().userId,
          };
          apiBaseHelper.postAPICall(removeFromCartApi, parameter).then(
            (getdata) {
              final bool error = getdata["error"];
              final String? msg = getdata["message"];
              if (!error) {
                final data = getdata["data"];
                if (from == 1) {
                  print(
                    "curCartCount***${context.read<UserProvider>().curCartCount}",
                  );
                  cartList.removeWhere(
                    (item) => item.varientId == cartList[index].varientId,
                  );
                  context.read<UserProvider>().setCartCount(data['total_items']);
                  originalPrice = double.parse(data[SUB_TOTAL]);
                  if (IS_SHIPROCKET_ON == "0") {
                    if (!ISFLAT_DEL) {
                      if (addressList.isNotEmpty &&
                          originalPrice <
                              double.parse(
                                addressList[selectedAddress!].freeAmt!,
                              )) {
                        deliveryCharge = double.parse(
                          addressList[selectedAddress!].deliveryCharge!,
                        );
                      } else {
                        deliveryCharge = 0;
                      }
                    } else {
                      if (originalPrice < double.parse(MIN_AMT!)) {
                        deliveryCharge = double.parse(CUR_DEL_CHR!);
                      } else {
                        deliveryCharge = 0;
                      }
                    }
                  }
                  totalPrice = 0;
                  totalPrice = originalPrice;
                  if (isPromoValid!) {
                    validatePromo(false);
                  } else if (isUseWallet!) {
                    context.read<CartProvider>().setProgress(false);
                    if (mounted) {
                      setState(() {
                        remWalBal = 0;
                        paymentMethod = null;
                        usedBalance = 0;
                        isPayLayShow = true;
                        isUseWallet = false;
                      });
                    }
                  }
                } else {
                  cartList.removeWhere(
                    (item) => item.varientId == cartList[index].varientId,
                  );
                }
                context.read<CartProvider>().setProgress(false);
                setState(() {});
              } else {
                setSnackbar(msg!, context);
              }
              if (mounted) setState(() {});
              checkoutState?.call(() {});
              context.read<CartProvider>().setProgress(false);
            },
            onError: (error) {
              setSnackbar(error.toString(), context);
            },
          );
        } on TimeoutException catch (_) {
          setSnackbar(getTranslated(context, 'somethingMSg')!, context);
          context.read<CartProvider>().setProgress(false);
        }
      } else {
        if (mounted) {
          setState(() {
            _isNetworkAvailable = false;
          });
        }
      }
    }

    removeFromCart(
      int index,
      bool remove,
      List<SectionModel> cartList,
      bool move,
      int selPos,
    ) async {
      _isNetworkAvailable = await isNetworkAvailable();
      if (!remove &&
          int.parse(cartList[index].qty!) ==
              cartList[index].productList![0].minOrderQuntity) {
        setSnackbar(
          "${getTranslated(context, 'MIN_MSG')}${cartList[index].qty}",
          context,
        );
      } else {
        if (_isNetworkAvailable) {
          try {
            context.read<CartProvider>().setProgress(true);
            int? qty;
            if (remove) {
              qty = 0;
            } else {
              qty = int.parse(cartList[index].qty!) -
                  int.parse(cartList[index].productList![0].qtyStepSize!);
              if (qty < cartList[index].productList![0].minOrderQuntity!) {
                qty = cartList[index].productList![0].minOrderQuntity;
                setSnackbar("${getTranslated(context, 'MIN_MSG')}$qty", context);
              }
            }
            String varId;
            if (cartList[index].productList![0].availability == "0") {
              varId = cartList[index].productList![0].prVarientList![selPos].id!;
            } else {
              varId = cartList[index].varientId!;
            }
            final parameter = {
              PRODUCT_VARIENT_ID: varId,
              USER_ID: context.read<UserProvider>().userId,
              QTY: qty.toString(),
            };
            apiBaseHelper.postAPICall(manageCartApi, parameter).then(
              (getdata) {
                final bool error = getdata["error"];
                final String? msg = getdata["message"];
                if (!error) {
                  final data = getdata["data"];
                  final String? qty = data['total_quantity'];
                  context.read<UserProvider>().setCartCount(data['cart_count']);
                  if (move == false) {
                    if (qty == "0") remove = true;
                    if (remove) {
                      cartList.removeWhere(
                        (item) => item.varientId == cartList[index].varientId,
                      );
                    } else {
                      cartList[index].qty = qty.toString();
                    }
                    originalPrice = double.parse(data[SUB_TOTAL]);
                    if (IS_SHIPROCKET_ON == "0") {
                      if (!ISFLAT_DEL) {
                        if (addressList.isNotEmpty &&
                            originalPrice <
                                double.parse(
                                  addressList[selectedAddress!].freeAmt!,
                                )) {
                          deliveryCharge = double.parse(
                            addressList[selectedAddress!].deliveryCharge!,
                          );
                        } else {
                          deliveryCharge = 0;
                        }
                      } else {
                        if (originalPrice < double.parse(MIN_AMT!)) {
                          deliveryCharge = double.parse(CUR_DEL_CHR!);
                        } else {
                          deliveryCharge = 0;
                        }
                      }
                    }
                    totalPrice = 0;
                    totalPrice = originalPrice;
                    if (isPromoValid!) {
                      validatePromo(false);
                    } else if (isUseWallet!) {
                      context.read<CartProvider>().setProgress(false);
                      if (mounted) {
                        setState(() {
                          remWalBal = 0;
                          paymentMethod = null;
                          usedBalance = 0;
                          isPayLayShow = true;
                          isUseWallet = false;
                        });
                      }
                    } else {
                      context.read<CartProvider>().setProgress(false);
                      setState(() {});
                    }
                  } else {
                    if (qty == "0") remove = true;
                    if (remove) {
                      cartList.removeWhere(
                        (item) => item.varientId == cartList[index].varientId,
                      );
                    }
                  }
                } else {
                  setSnackbar(msg!, context);
                }
                if (mounted) setState(() {});
                context.read<CartProvider>().setProgress(false);
              },
              onError: (error) {
                setSnackbar(error.toString(), context);
              },
            );
          } on TimeoutException catch (_) {
            setSnackbar(getTranslated(context, 'somethingMSg')!, context);
            context.read<CartProvider>().setProgress(false);
          }
        } else {
          if (mounted) {
            setState(() {
              _isNetworkAvailable = false;
            });
          }
        }
      }
    }

    _showContent1(BuildContext context) {
      final List<SectionModel> cartList = context.read<CartProvider>().cartList;
      return _isCartLoad || _isSaveLoad
          ? shimmer(context)
          : cartList.isEmpty && saveLaterList.isEmpty
              ? cartEmpty(context)
              : Container(
                  color: Theme.of(context).colorScheme.lightWhite,
                  padding: const EdgeInsets.only(bottom: 60),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10.0),
                          child: RefreshIndicator(
                            color: Theme.of(context).colorScheme.primarytheme,
                            key: _refreshIndicatorKey,
                            onRefresh: _refresh,
                            child: SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              controller: _scrollControllerOnCartItems,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ListView.builder(
                                    shrinkWrap: true,
                                    itemCount: cartList.length,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemBuilder: (context, index) {
                                      return listItem(index, cartList);
                                    },
                                  ),
                                  if (saveLaterList.isNotEmpty &&
                                      proVarIds.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Text(
                                        getTranslated(
                                          context,
                                          'SAVEFORLATER_BTN',
                                        )!,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium!
                                            .copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .fontColor,
                                            ),
                                      ),
                                    )
                                  else
                                    Container(height: 0),
                                  if (saveLaterList.isNotEmpty &&
                                      proVarIds.isNotEmpty)
                                    ListView.builder(
                                      shrinkWrap: true,
                                      itemCount: saveLaterList.length,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      itemBuilder: (context, index) {
                                        return saveLaterItem(index);
                                      },
                                    ),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      if (context
                                          .read<CartProvider>()
                                          .cartList
                                          .isNotEmpty)
                                        Container(
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .white,
                                            borderRadius: const BorderRadius.all(
                                              Radius.circular(5),
                                            ),
                                          ),
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 8,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                            horizontal: 5,
                                          ),
                                          child: Column(
                                            children: [
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Text(
                                                    getTranslated(
                                                      context,
                                                      'TOTAL_PRICE',
                                                    )!,
                                                  ),
                                                  
  buildConvertedPrice(
  context,
  originalPrice,
  style: Theme.of(context).textTheme.titleMedium!.copyWith(
    color: Theme.of(context).colorScheme.fontColor,
  ),
),


                                                ],
                                              ),
                                            ],
                                          ),
                                        )
                                      else
                                        Container(
                                          height: 0,
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (cartList.isNotEmpty)
                        Center(
                          child: SimBtn(
                            width: 0.9,
                            height: 35,
                            title: getTranslated(context, 'PROCEED_CHECKOUT'),
                            onBtnSelected: () async {
                              final result = await Navigator.pushNamed(
                                context,
                                Routers.loginScreen,
                                arguments: {
                                  "isRefresh": true,
                                  "isPop": true,
                                  "classType":
                                      Cart(fromBottom: widget.fromBottom),
                                },
                              );
                              if (result == 'refresh') {
                                _refresh();
                              }
                            },
                          ),
                        )
                      else
                        Container(
                          height: 0,
                        ),
                    ],
                  ),
                );
    }

    _showContent(BuildContext context) {
      final List<SectionModel> cartList = context.read<CartProvider>().cartList;
      return _isCartLoad
          ? shimmer(context)
          : cartList.isEmpty && saveLaterList.isEmpty
              ? cartEmpty(context)
              : Container(
                  padding: const EdgeInsets.only(bottom: 60),
                  color: Theme.of(context).colorScheme.lightWhite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: RefreshIndicator(
                          color: Theme.of(context).colorScheme.primarytheme,
                          key: _refreshIndicatorKey,
                          onRefresh: _refresh,
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            controller: _scrollControllerOnCartItems,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (cartList.isNotEmpty)
                                  ListView.builder(
                                    padding: EdgeInsets.zero,
                                    shrinkWrap: true,
                                    itemCount: cartList.length,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemBuilder: (context, index) {
                                      return listItem(index, cartList);
                                    },
                                  ),
                                if (saveLaterList.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Text(
                                      getTranslated(
                                        context,
                                        'SAVEFORLATER_BTN',
                                      )!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium!
                                          .copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .fontColor,
                                          ),
                                    ),
                                  ),
                                if (saveLaterList.isNotEmpty)
                                  ListView.builder(
                                    shrinkWrap: true,
                                    itemCount: saveLaterList.length,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemBuilder: (context, index) {
                                      return saveLaterItem(index);
                                    },
                                  ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    if (promoList.isNotEmpty && originalPrice > 0)
                                      Padding(
                                        padding: const EdgeInsets.all(5.0),
                                        child: Stack(
                                          alignment: Alignment.centerRight,
                                          children: [
                                            Container(
                                              margin: const EdgeInsetsDirectional
                                                  .only(end: 20),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .white,
                                                borderRadius:
                                                    BorderRadiusDirectional
                                                        .circular(5),
                                              ),
                                              child: TextField(
                                                textDirection: Directionality.of(
                                                  context,
                                                ),
                                                controller: promoCodeController,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleSmall,
                                                decoration: InputDecoration(
                                                  contentPadding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                  ),
                                                  border: InputBorder.none,
                                                  hintText: getTranslated(
                                                        context,
                                                        'PROMOCODE_LBL',
                                                      ) ??
                                                      '',
                                                ),
                                                onChanged: (val) {
                                                  setState(() {
                                                    if (val.isEmpty) {
                                                      isPromoLen = false;
                                                      isPromoValid = false;
                                                      promoEmpty().then((value) {
                                                        promoAmount = 0;
                                                      });
                                                    } else {
                                                      isPromoLen = true;
                                                      isPromoValid = false;
                                                    }
                                                  });
                                                },
                                              ),
                                            ),
                                            Positioned.directional(
                                              textDirection:
                                                  Directionality.of(context),
                                              end: 0,
                                              child: InkWell(
                                                onTap: () {
                                                  if (promoCodeController
                                                      .text.isEmpty) {
                                                    Navigator.pushNamed(
                                                      context,
                                                      Routers.promoCodeScreen,
                                                      arguments: {
                                                        "from": "cart",
                                                        "updateParent":
                                                            updatePromo,
                                                      },
                                                    );
                                                  }
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.all(
                                                    11,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primarytheme,
                                                  ),
                                                  child: Icon(
                                                    Icons.arrow_forward,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .white,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (cartList.isNotEmpty)
                                      Container(
                                        decoration: BoxDecoration(
                                          color:
                                              Theme.of(context).colorScheme.white,
                                          borderRadius: const BorderRadius.all(
                                            Radius.circular(5),
                                          ),
                                        ),
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 8,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 10,
                                          horizontal: 8,
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (isPromoValid!)
                                              if (!isPromoLen)
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Text(
                                                      getTranslated(
                                                        context,
                                                        'PROMO_CODE_DIS_LBL',
                                                      )!,
                                                      style: Theme.of(
                                                        context,
                                                      )
                                                          .textTheme
                                                          .bodySmall!
                                                          .copyWith(
                                                            color: Theme.of(
                                                              context,
                                                            )
                                                                .colorScheme
                                                                .lightBlack2,
                                                          ),
                                                    ),
                                                    buildConvertedPrice(
  context,
  promoAmount,
  style: Theme.of(context).textTheme.bodySmall!.copyWith(
        color: Theme.of(context).colorScheme.lightBlack2,
      ),
),

                                                  ],
                                                ),
                                            if (cartList.isNotEmpty)
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Text(
                                                    getTranslated(
                                                      context,
                                                      'TOTAL_PRICE',
                                                    )!,
                                                  ),
                                                  buildConvertedPrice(
  context,
  originalPrice,
  style: Theme.of(context).textTheme.titleMedium!.copyWith(
    color: Theme.of(context).colorScheme.fontColor,
  ),
)

                                                ],
                                              ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (cartList.isNotEmpty &&
                              cartList[0].productList![0].productType !=
                                  'digital_product')
                            if (IS_LOCAL_PICKUP == "1")
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: <Widget>[
                                  Expanded(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Radio(
                                          fillColor: WidgetStateColor.resolveWith(
                                            (states) {
                                              return Theme.of(context)
                                                  .colorScheme
                                                  .primarytheme;
                                            },
                                          ),
                                          groupValue: isStorePickUp,
                                          value: "false",
                                          onChanged: (val) {
                                            setState(() {
                                              isStorePickUp = val.toString();
                                              {}
                                            });
                                          },
                                        ),
                                        Expanded(
                                          child: Text(
                                            getTranslated(
                                              context,
                                              'DOOR_STEP_DEL_LBL',
                                            )!,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall!
                                                .copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .fontColor,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Radio(
                                          fillColor: WidgetStateColor.resolveWith(
                                            (states) {
                                              return Theme.of(context)
                                                  .colorScheme
                                                  .primarytheme;
                                            },
                                          ),
                                          hoverColor: Theme.of(context)
                                              .colorScheme
                                              .primarytheme,
                                          groupValue: isStorePickUp,
                                          value: "true",
                                          onChanged: (val) {
                                            setState(() {
                                              isStorePickUp = val.toString();
                                            });
                                          },
                                        ),
                                        Expanded(
                                          child: Text(
                                            getTranslated(
                                              context,
                                              'PICKUP_STORE_LBL',
                                            )!,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall!
                                                .copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .fontColor,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                          Center(
                            child: SimBtn(
                              width: 0.9,
                              height: 35,
                              title: isPromoLen
                                  ? getTranslated(context, 'VALI_PRO_CODE')
                                  : getTranslated(context, 'PROCEED_CHECKOUT'),
                              onBtnSelected: () async {
                                print(
                                  "isavaileble check***$isAvailable***$totalPrice****$originalPrice",
                                );
                                if (isPromoLen == false) {
                                  if (originalPrice > 0) {
                                    FocusScope.of(context).unfocus();
                                    if (isAvailable) {
                                      checkout();
                                    } else {
                                      setSnackbar(
                                        getTranslated(
                                          context,
                                          'CART_OUT_OF_STOCK_MSG',
                                        )!,
                                        context,
                                      );
                                    }
                                    if (mounted) setState(() {});
                                  } else {
                                    setSnackbar(
                                      getTranslated(context, 'ADD_ITEM')!,
                                      context,
                                    );
                                  }
                                } else {
                                  validatePromo(false).then((value) {
                                    FocusScope.of(context).unfocus();
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
    }

    Future<void> promoEmpty() async {
      setState(() {
        totalPrice = totalPrice + promoAmount;
      });
    }

  Future<void> checkout() async {
  final List<SectionModel> cartList = context.read<CartProvider>().cartList;
  print("cartList*****${cartList.length}");
  deviceHeight = MediaQuery.of(context).size.height;
  deviceWidth = MediaQuery.of(context).size.width;

  // Ensure SkipCash is the selected payment method and fetch time slots
  paymentMethod = getTranslated(context, 'SKIPCASH_LBL');
  _getdateTime();

  if (isStorePickUp == "false" &&
      addressList.isNotEmpty &&
      !deliverable &&
      cartList[0].productList![0].productType != 'digital_product') {
    checkDeliverable(2);
  }

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(10),
        topRight: Radius.circular(10),
      ),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          checkoutState = setState;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => FocusScope.of(context).unfocus(),
            child: SafeArea(
              bottom: Platform.isAndroid ? false : true,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                child: Scaffold(
                  resizeToAvoidBottomInset: false,
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  body: _isNetworkAvailable
                      ? cartList.isEmpty
                          ? cartEmpty(context)
                          : _isLoading
                              ? shimmer(context)
                              : Column(
                                  children: [
                                    Expanded(
                                      child: SingleChildScrollView(
                                        keyboardDismissBehavior:
                                            ScrollViewKeyboardDismissBehavior.onDrag,
                                        child: Padding(
                                          padding: const EdgeInsets.all(10.0),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (cartList[0].productList![0].productType !=
                                                  'digital_product')
                                                (IS_LOCAL_PICKUP != "1" ||
                                                        isStorePickUp != "true")
                                                    ? address()
                                                    : const SizedBox.shrink()
                                              else
                                                const SizedBox.shrink(),
                                              attachPrescriptionImages(cartList),
                                              payment(),
                                              cartItems(cartList),
                                              orderSummary(cartList),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 20),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).colorScheme.white,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black12,
                                              offset: Offset(0, -1),
                                              blurRadius: 4,
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          children: [
                                            Padding(
                                              padding: const EdgeInsetsDirectional.only(start: 15),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  buildTotalPriceWidget(context),
                                                  Text("${cartList.length} Items"),
                                                ],
                                              ),
                                            ),
                                            const Spacer(),
                                            Padding(
                                              padding: const EdgeInsets.only(right: 10),
                                              child: SimBtn(
                                                height: 35,
                                                width: 0.4,
                                                title: getTranslated(context, 'PLACE_ORDER'),
                                                onBtnSelected: () async {
                                                  checkoutState?.call(() {
                                                    _placeOrder = false;
                                                  });

                                                  if (paymentMethod == null || paymentMethod!.isEmpty) {
                                                    msg = getTranslated(context, 'payWarning');
                                                    setSnackbar(msg!, context);
                                                    checkoutState?.call(() {
                                                      _placeOrder = true;
                                                    });
                                                    return;
                                                  }

                                                  if ((selDate == null || selDate!.isEmpty) && startingDate != null) {
                                                    final DateTime first = DateTime.parse(startingDate!);
                                                    selDate = DateFormat('yyyy-MM-dd').format(first);
                                                    selectedDate ??= 0;
                                                  }

                                                  if ((selTime == null || selTime!.isEmpty) && timeSlotList.isNotEmpty) {
                                                    selTime = timeSlotList[0].name;
                                                    selectedTime ??= 0;
                                                  }

                                                  if (double.parse(MIN_ALLOW_CART_AMT!) > originalPrice) {
                                                    setSnackbar(getTranslated(context, 'MIN_CART_AMT')!, context);
                                                    return;
                                                  }

                                                  if (cartList[0].productList![0].productType !=
                                                          'digital_product' &&
                                                      isStorePickUp == "false" &&
                                                      !deliverable) {
                                                    checkDeliverable(1);
                                                    return;
                                                  }

                                                 if (!context.read<CartProvider>().isProgress) {
                                                   if (cartList[0].productList![0].productType ==
                                                       'digital_product') {
                                                     if (mobileController.text.trim().isEmpty) {
                                                       setSnackbar(
                                                         getTranslated(context, 'MOBILE_REQUIRED') ??
                                                             'Mobile number is required',
                                                         context,
                                                       );
                                                       checkoutState?.call(() {
                                                         _placeOrder = true;
                                                       });
                                                       return;
                                                     }

                                                     final String? emailError = validateEmail(
                                                       emailController.text.trim(),
                                                       getTranslated(context, 'EMAIL_REQUIRED'),
                                                       getTranslated(context, 'VALID_EMAIL'),
                                                     );
                                                     if (emailError != null) {
                                                       setSnackbar(emailError, context);
                                                       checkoutState?.call(() {
                                                         _placeOrder = true;
                                                       });
                                                       return;
                                                     }
                                                   }
                                                   placeOrder('');
                                                 }
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                      : noInternet(
                          context,
                          buttonController: buttonController,
                          buttonSqueezeanimation: buttonSqueezeanimation,
                          onButtonClicked: (internetAvailable) {
                            _isNetworkAvailable = internetAvailable;
                            callApi();
                            setState(() {});
                          },
                          onNetworkNavigationWidget: super.widget,
                        ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

Widget buildTotalPriceWidget(BuildContext context) {
  double finalPrice = totalPrice;
  if (usedBalance == 0 && isStorePickUp == "false") {
  finalPrice = totalPrice + deliveryCharge;
}

  return buildConvertedPrice(
    context,
    finalPrice,
    style: Theme.of(context).textTheme.titleMedium!.copyWith(
      color: Theme.of(context).colorScheme.fontColor,
      fontWeight: FontWeight.bold,
    ),
  );
}

    

    

    updateCheckout() {
      if (mounted) checkoutState?.call(() {});
    }

    updateProgress(bool progress) {
      if (mounted) {
        checkoutState?.call(() {
          context.read<CartProvider>().setProgress(progress);
        });
      }
    }

    razorpayPayment(String orderID, String? msg) async {
      print("razorpay here");
      final SettingProvider settingsProvider =
          Provider.of<SettingProvider>(context, listen: false);
      final String contact = settingsProvider.mobile;
      final String email = settingsProvider.email;
      final String amt = ((usedBalance > 0
                  ? totalPrice
                  : isStorePickUp == "false"
                      ? (totalPrice + deliveryCharge)
                      : totalPrice) *
              100)
          .toStringAsFixed(2);
      context.read<CartProvider>().setProgress(true);
      checkoutState?.call(() {});
      
    }

    Future<void> paytmPayment(
      String? tranId,
      String orderID,
      String? status,
      String? msg,
      bool redirect,
    ) async {
      context.read<CartProvider>().setProgress(true);
      final String orderId = DateTime.now().millisecondsSinceEpoch.toString();
      final String callBackUrl =
          '${payTesting ? 'https://securegw-stage.paytm.in' : 'https://securegw.paytm.in'}/theia/paytmCallback?ORDER_ID=$orderId';
      final parameter = {
        AMOUNT: usedBalance > 0
            ? totalPrice.toString()
            : isStorePickUp == "false"
                ? (totalPrice + deliveryCharge).toString()
                : totalPrice.toString(),
        USER_ID: context.read<UserProvider>().userId,
        ORDER_ID: orderId,
      };
      
    }

    

    

    

    String generateSha256Hash(String input) {
      final bytes = utf8.encode(input);
      final digest = sha256.convert(bytes);
      return digest.toString();
    }


Future<void> placeOrder(String? tranId) async {
  // Check network connectivity.
  _isNetworkAvailable = await isNetworkAvailable();
  if (!_isNetworkAvailable) {
    if (mounted) {
      checkoutState?.call(() {
        _isNetworkAvailable = false;
      });
    }
    return;
  }

  final cartProvider = context.read<CartProvider>();
  final userProvider = context.read<UserProvider>();
  cartProvider.setProgress(true);

  // Calculate cart string values.
  String? varientId;
  String? quantity;
  final List<SectionModel> cartList = cartProvider.cartList;
  for (final SectionModel sec in cartList) {
    varientId = varientId != null ? "$varientId,${sec.varientId!}" : sec.varientId;
    quantity = quantity != null ? "$quantity,${sec.qty!}" : sec.qty;
  }

  // Determine payment method string.
  String? payVia;
  if (paymentMethod == getTranslated(context, 'COD_LBL')) {
    payVia = "COD";
  } else if (paymentMethod == getTranslated(context, 'STRIPE_LBL')) {
    payVia = "Stripe";
  } else if (paymentMethod == "Wallet") {
    payVia = "Wallet";
  } else if (paymentMethod == getTranslated(context, 'BANKTRAN')) {
    payVia = "bank_transfer";
  } else if (paymentMethod == getTranslated(context, 'MY_FATOORAH_LBL')) {
    payVia = "my fatoorah";
  }

  // ───────────────────────────────
  // SKIPCASH integration branch
  // If SkipCash is selected, call the dedicated initiateSkipCashPayment function,
  // which will handle the SkipCash payment flow (opening the webview, callbacks, etc.).
  if (paymentMethod == getTranslated(context, 'SKIPCASH_LBL')) {
    // Calculate final amount.
    double finalAmount = usedBalance > 0
        ? totalPrice
        : isStorePickUp == "false"
            ? (totalPrice + deliveryCharge)
            : totalPrice;
    // Generate an order ID placeholder. Replace with an actual generated order ID if available.
    final String orderIdForPayment = '';
    print('MOBILE CONTROLLER VALUE: ${mobileController.text.trim()}');


    final String checkoutMobile = mobileController.text.trim().isNotEmpty
    ? mobileController.text.trim()
     : (userProvider.mobile ?? '');

    await initiateSkipCashPayment(
      context,
      orderIdForPayment,
      finalAmount,
      totalPrice: totalPrice,
      deliveryCharge: deliveryCharge,
      usedBalance: usedBalance,
      isStorePickUp: isStorePickUp,
      selDate: selDate,
      selTime: selTime,
      baseUrl: baseUrl,
      placeOrder: placeOrder,
      accountPhone: userProvider.mobile ?? '97433277077',
  checkoutMobile: checkoutMobile, // Pass this callback to be called upon completion.
    );
    return; // Stop further order placement until SkipCash payment completes.
  }
  // ───────────────────────────────
  // END SkipCash Branch

  // Normal order placement for other payment methods
  final request = http.MultipartRequest("POST", placeOrderApi);
  request.headers.addAll(headers);
request.fields['mobile'] = mobileController.text.trim();     // User's checkout entry
request.fields['account_mobile'] = userProvider.mobile ?? ''; // Saved profile/account
  request.fields[USER_ID] = userProvider.userId;
  request.fields[PRODUCT_VARIENT_ID] = varientId!;
  request.fields[QUANTITY] = quantity!;
  request.fields[TOTAL] = originalPrice.toString();
  request.fields[FINAL_TOTAL] = usedBalance > 0
      ? totalPrice.toString()
      : isStorePickUp == "false"
          ? (totalPrice + deliveryCharge).toString()
          : totalPrice.toString();
  request.fields[TAX_PER] = taxPersontage.toString();
  request.fields[PAYMENT_METHOD] = payVia!;
  request.fields[ISWALLETBALUSED] = isUseWallet! ? "1" : "0";
  request.fields[WALLET_BAL_USED] = usedBalance.toString();
  request.fields[ORDER_NOTE] = noteC.text;
  
  if (IS_LOCAL_PICKUP != "1" || isStorePickUp != "true") {
    request.fields[DEL_CHARGE] = deliveryCharge.toString();
  }
  
  final selectedMosque = context.read<MosqueProvider>().selectedMosque;
  request.fields[ADD_ID] = selectedMosque != null ? selectedMosque.id : "999";
  if (IS_LOCAL_PICKUP == "1") {
    request.fields[LOCAL_PICKUP] = isStorePickUp == "true" ? "1" : "0";
  }
  request.fields[ACTIVE_STATUS] = paymentMethod == getTranslated(context, 'COD_LBL') ? PLACED : WAITING;

  try {
    // Attach prescription images if available.
    if (prescriptionImages.isNotEmpty) {
      for (var i = 0; i < prescriptionImages.length; i++) {
        final mimeType = lookupMimeType(prescriptionImages[i].path);
        final extension = mimeType!.split("/");
        final pic = await http.MultipartFile.fromPath(
          DOCUMENT,
          prescriptionImages[i].path,
          contentType: MediaType('image', extension[1]),
        );
        request.files.add(pic);
      }
    }
    final response = await request.send();
    final responseData = await response.stream.toBytes();
    final responseString = String.fromCharCodes(responseData);
    _placeOrder = true;
    final getdata = json.decode(responseString);

    if (response.statusCode == 200 && !getdata["error"]) {
      context.read<UserProvider>().setBalance(getdata["data"]["balance"]);
      final String orderId = getdata["data"]["order_id"].toString();

      // Handle other payment-specific routing.
      if (paymentMethod == getTranslated(context, 'RAZORPAY_LBL')) {
        razorpayPayment(orderId, getdata["message"]);
      } else if (paymentMethod == getTranslated(context, 'STRIPE_LBL')) {
        stripePayment(stripePayId, orderId, tranId == 'succeeded' ? PLACED : WAITING, getdata["message"], true);
      } else if (paymentMethod == getTranslated(context, 'PAYTM_LBL')) {
        paytmPayment(tranId, orderId, SUCCESS, getdata["message"], true);
      } else if (paymentMethod == getTranslated(context, 'FLUTTERWAVE_LBL')) {
        flutterwavePayment(tranId, orderId, SUCCESS, getdata["message"], true);
      } else if (paymentMethod == getTranslated(context, 'MIDTRANS_LBL')) {
        midTrasPayment(orderId, tranId == 'succeeded' ? PLACED : WAITING, getdata["message"], true);
      } else if (paymentMethod == getTranslated(context, 'MY_FATOORAH_LBL')) {
        fatoorahPayment(tranId, orderId, tranId == 'succeeded' ? PLACED : WAITING, getdata["message"], true);
      } else {
        // Default: clear the cart and navigate to order success screen.
        context.read<UserProvider>().setCartCount("0");
        clearCart();
        Navigator.pushNamedAndRemoveUntil(
          context,
          Routers.orderSuccessScreen,
          (route) => route.isFirst,
        );
      }
    } else {
      setSnackbar(getdata["message"], context);
    }
  } on TimeoutException catch (_) {
    checkoutState?.call(() {
      _placeOrder = true;
    });
    context.read<CartProvider>().setProgress(false);
  } finally {
    context.read<CartProvider>().setProgress(false);
  }
}


Future<void> initiateSkipCashPayment(
  BuildContext context,
  String orderId,
  double amount, {
  required double totalPrice,
  required double deliveryCharge,
  required double usedBalance,
  required String isStorePickUp,
  required String? selDate,
  required String? selTime,
    required String accountPhone,
  required String checkoutMobile,
  required String baseUrl,
  required Future<void> Function(String?) placeOrder,
}) async {
  final Logger log = Logger('SkipCashPayment');
  log.info('START: initiateSkipCashPayment called with orderId: $orderId, amount: $amount');

  if (!context.mounted) {
    log.severe('Context not mounted, aborting.');
    return;
  }

  final cartProvider = context.read<CartProvider>();
  final userProvider = context.read<UserProvider>();
  final String? jwtToken = HiveUtils.getJWT();

  if (jwtToken == null || jwtToken.isEmpty) {
    setSnackbar('Please log in again to proceed with payment', context);
    Navigator.pushReplacementNamed(context, '/login');
    return;
  }

  if (cartProvider.cartList.isEmpty) {
    setSnackbar('Cart is empty', context);
    return;
  }

  // Build comma-separated lists of variants & quantities:
  final variantIds = cartProvider.cartList.map((e) => e.varientId).join(',');
  final quantities = cartProvider.cartList.map((e) => e.qty).join(',');

  final double finalAmount = usedBalance > 0
      ? totalPrice
      : (isStorePickUp == "false" ? totalPrice + deliveryCharge : totalPrice);

  if (finalAmount <= 0) {
    setSnackbar('Invalid payment amount', context);
    return;
  }

  final nameParts = userProvider.userName.split(' ');
  final firstName = nameParts.first;
  final lastName = nameParts.length > 1 ? nameParts[1] : '';

  
  final String email = userProvider.email.isNotEmpty
      ? userProvider.email
      : '';

  // Make sure you have your selected mosque here:
  final selectedMosque = context.read<MosqueProvider>().selectedMosque;

  final cartData = {
    'total':              totalPrice,
    'delivery_charge':    deliveryCharge,
    'product_variant_id': variantIds,
    'quantity':           quantities,
    'user_id':            userProvider.userId,
    'address_id':         selectedMosque?.id ?? '999',
    'local_pickup':       isStorePickUp == "true" ? '1' : '0',
    'mosque_name':        selectedMosque?.name ?? '',
    'delivery_date':      selDate,
    'delivery_time':      selTime,
  };

  final body = {
    'amount':    finalAmount.toStringAsFixed(2),
    'order_id':  orderId,
    'device_os': Platform.isAndroid ? 'android' : 'ios',
    'fcm_id':    '',
    'cart_data': cartData,
    'first_name': firstName,
    'last_name':  lastName,
    'account_mobile': accountPhone,
  'phone': checkoutMobile.isNotEmpty
      ? checkoutMobile
      : (accountPhone.isNotEmpty ? accountPhone : '97433277077'),

    'email':      email,
  };

  try {
    final effectivePhone = checkoutMobile.isNotEmpty
    ? checkoutMobile
    : userProvider.mobile ?? '';
if (effectivePhone.isEmpty) {
  setSnackbar('Please enter your phone number to proceed with payment', context);
  return;
}

    cartProvider.setProgress(true);
    log.info('Calling SkipCash API at: ${baseUrl}skipcash');

    final response = await http.post(
      Uri.parse('${baseUrl}skipcash'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwtToken',
      },
      body: jsonEncode(body),
    );

    final data = jsonDecode(response.body);
    log.info('SkipCash response: $data');

    if (response.statusCode == 200 && data['error'] == false && data['resultObj'] != null) {
      final result = data['resultObj'];
      if (result['status'] == 'paid') {
        await placeOrder(result['transactionId'] ?? 'skipcash-$orderId');
      } else if (result['status'] == 'new' && result['payUrl'] != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SkipCashWebView(
              payUrl: result['payUrl'],
              paymentId: result['transactionId'],
              onSuccess: (txId) => placeOrder(txId),
              onError: (err) {
                setSnackbar(err, context);
                deleteOrders(orderId);
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ),
        );
      } else {
        setSnackbar('SkipCash payment not completed', context);
      }
    } else {
      setSnackbar(data['message'] ?? 'SkipCash payment failed', context);
    }
  } catch (e, st) {
    log.severe('SkipCash exception', e, st);
    setSnackbar('Something went wrong: $e', context);
  } finally {
    cartProvider.setProgress(false);
    log.info('END: initiateSkipCashPayment');
  }
}





void setSnackbar(String message, BuildContext context) {
  _log.info('Showing snackbar: $message, context.mounted=${context.mounted}');
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  } else {
    _log.warning('Cannot show snackbar, context not mounted');
  }
}


    

   

    Future<void> addTransaction(
      String? tranId,
      String orderID,
      String? status,
      String? msg,
      bool redirect,
    ) async {
      try {
        final parameter = {
          USER_ID: context.read<UserProvider>().userId,
          ORDER_ID: orderID,
          TYPE: paymentMethod,
          TXNID: tranId,
          AMOUNT: usedBalance > 0
              ? totalPrice.toString()
              : isStorePickUp == "false"
                  ? (totalPrice + deliveryCharge).toString()
                  : totalPrice.toString(),
          STATUS: status,
          MSG: msg,
        };
        print("transaction param*****$parameter");
        apiBaseHelper.postAPICall(addTransactionApi, parameter).then(
          (getdata) {
            final bool error = getdata["error"];
            final String? msg1 = getdata["message"];
            if (!error) {
              if (redirect) {
                context.read<UserProvider>().setCartCount("0");
                clearCart();
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  Routers.orderSuccessScreen,
                  (route) => route.isFirst,
                );
              }
            } else {
              setSnackbar(msg1!, context);
            }
          },
          onError: (error) {
            setSnackbar(error.toString(), context);
          },
        );
      } on TimeoutException catch (_) {
        setSnackbar(getTranslated(context, 'somethingMSg')!, context);
      }
    }

    Future<void> deleteOrders(String orderId) async {
      try {
        final parameter = {
          ORDER_ID: orderId,
        };
        apiBaseHelper.postAPICall(deleteOrderApi, parameter).then(
          (getdata) {
            if (mounted) {
              setState(() {});
            }
            Navigator.of(context).pop();
          },
          onError: (error) {
            setSnackbar(error.toString(), context);
          },
        );
      } on TimeoutException catch (_) {
        setSnackbar(getTranslated(context, 'somethingMSg')!, context);
        setState(() {});
      }
    }

  

    String _getReference() {
      String platform;
      if (Platform.isIOS) {
        platform = 'iOS';
      } else {
        platform = 'Android';
      }
      return 'ChargedFrom${platform}_${DateTime.now().millisecondsSinceEpoch}';
    }

    midTrasPayment(
      String orderID,
      String? status,
      String? msg,
      bool redirect,
    ) async {
      _isNetworkAvailable = await isNetworkAvailable();
      if (_isNetworkAvailable) {
        try {
          context.read<CartProvider>().setProgress(true);
          final parameter = {
            AMOUNT: ((usedBalance > 0
                            ? totalPrice
                            : isStorePickUp == "false"
                                ? (totalPrice + deliveryCharge)
                                : totalPrice)
                        .toInt() *
                    100)
                .toString(),
            USER_ID: context.read<UserProvider>().userId,
            ORDER_ID: orderID,
          };
          apiBaseHelper.postAPICall(createMidtransTransactionApi, parameter).then(
            (getdata) {
              final bool error = getdata['error'];
              final String? msg = getdata['message'];
              if (!error) {
                final data = getdata['data'];
                final String redirectUrl = data['redirect_url'];
                Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (BuildContext context) => MidTrashWebview(
                      url: redirectUrl,
                      from: 'order',
                      orderId: orderID,
                    ),
                  ),
                ).then(
                  (value) async {
                    _isNetworkAvailable = await isNetworkAvailable();
                    if (_isNetworkAvailable) {
                      try {
                        context.read<CartProvider>().setProgress(true);
                        final parameter = {
                          ORDER_ID: orderID,
                        };
                        apiBaseHelper
                            .postAPICall(
                          getMidtransTransactionStatusApi,
                          parameter,
                        )
                            .then(
                          (getdata) async {
                            final bool error = getdata['error'];
                            final String? msg = getdata['message'];
                            final data = getdata['data'];
                            if (!error) {
                              final String statuscode = data['status_code'];
                              if (statuscode == '404') {
                                deleteOrders(orderID);
                                if (mounted) {
                                  setState(
                                    () {
                                      _placeOrder = true;
                                    },
                                  );
                                }
                                context.read<CartProvider>().setProgress(false);
                              }
                              if (statuscode == '200') {
                                final String transactionStatus =
                                    data['transaction_status'];
                                final String transactionId =
                                    data['transaction_id'];
                                if (transactionStatus == 'capture') {
                                  final Map<String, dynamic> result =
                                      await updateOrderStatus(
                                    orderID: orderID,
                                    status: PLACED,
                                  );
                                  if (!result['error']) {
                                    await addTransaction(
                                      transactionId,
                                      orderID,
                                      SUCCESS,
                                      msg,
                                      true,
                                    );
                                  } else {
                                    setSnackbar('${result['message']}', context);
                                  }
                                  if (mounted) {
                                    context
                                        .read<CartProvider>()
                                        .setProgress(false);
                                  }
                                } else {
                                  deleteOrders(orderID);
                                  if (mounted) {
                                    setState(() {
                                      _placeOrder = true;
                                    });
                                  }
                                  context.read<CartProvider>().setProgress(false);
                                }
                              }
                            } else {
                              setSnackbar(msg!, context);
                            }
                            context.read<CartProvider>().setProgress(false);
                          },
                          onError: (error) {
                            setSnackbar(error.toString(), context);
                          },
                        );
                      } on TimeoutException catch (_) {
                        context.read<CartProvider>().setProgress(false);
                        setSnackbar(
                          getTranslated(context, 'somethingMSg')!,
                          context,
                        );
                      }
                    } else {
                      if (mounted) {
                        setState(() {
                          _isNetworkAvailable = false;
                        });
                      }
                    }
                    if (value == 'true') {
                      setState(
                        () {
                          _placeOrder = true;
                        },
                      );
                    } else {}
                  },
                );
              } else {
                setSnackbar(msg!, context);
              }
              context.read<CartProvider>().setProgress(false);
            },
            onError: (error) {
              setSnackbar(error.toString(), context);
            },
          );
        } on TimeoutException catch (_) {
          context.read<CartProvider>().setProgress(false);
          setSnackbar(getTranslated(context, 'somethingMSg')!, context);
        }
      } else {
        if (mounted) {
          setState(() {
            _isNetworkAvailable = false;
          });
        }
      }
    }

    fatoorahPayment(
      String? tranId,
      String orderID,
      String? status,
      String? msg,
      bool redirect,
    ) async {
      _isNetworkAvailable = await isNetworkAvailable();
      if (_isNetworkAvailable) {
        try {
          final String amount = ((usedBalance > 0
                          ? totalPrice
                          : isStorePickUp == "false"
                              ? (totalPrice + deliveryCharge)
                              : totalPrice)
                      .toInt() *
                  100)
              .toString();
          final String successUrl =
              '${myfatoorahSuccessUrl!}?order_id=$orderID&amount=${double.parse(amount)}';
          final String errorUrl =
              '${myfatoorahErrorUrl!}?order_id=$orderID&amount=${double.parse(amount)}';
          final String token = myfatoorahToken!;
          context.read<CartProvider>().setProgress(true);
          print("suceesUrl****$successUrl****$errorUrl*****$token");
          final response = await MyFatoorah.startPayment(
            context: context,
            errorChild: InkWell(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red,
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 30,
                        color: Colors.white,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 10.0),
                      child: Text(
                        getTranslated(context, 'PAYMENT_FAILED_LBL')!,
                        style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                              color: Theme.of(context).colorScheme.fontColor,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 10.0),
                      child: Text(
                        getTranslated(context, 'TRY_AGAIN_INT_LBL')!,
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .fontColor
                                  .withOpacity(0.7),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              onTap: () {
                setSnackbar(
                  getTranslated(context, 'PAYMENT_FAILED_LBL')!,
                  context,
                );
                deleteOrders(orderID);
              },
            ),
            successChild: InkWell(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      getTranslated(context, 'PAYMENT_SUCCESS_LBL')!,
                      style: const TextStyle(
                        fontFamily: 'ubuntu',
                      ),
                    ),
                    const SizedBox(
                      width: 200,
                      height: 100,
                      child: Icon(
                        Icons.done,
                        size: 100,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
              onTap: () async {
                final paymentId = context.read<PaymentIdProvider>().paymentId;
                if (paymentId != null) {
                  await updateOrderStatus(orderID: orderID, status: PLACED);
                  addTransaction(
                    paymentId,
                    orderID,
                    SUCCESS,
                    msg,
                    true,
                  );
                }
              },
            ),
            request: myfatoorahPaymentMode == 'test'
                ? MyfatoorahRequest.test(
                    currencyIso: () {
                      if (myfatoorahCountry == 'Kuwait') {
                        return Country.Kuwait;
                      } else if (myfatoorahCountry == 'UAE') {
                        return Country.UAE;
                      } else if (myfatoorahCountry == 'Egypt') {
                        return Country.Egypt;
                      } else if (myfatoorahCountry == 'Bahrain') {
                        return Country.Bahrain;
                      } else if (myfatoorahCountry == 'Jordan') {
                        return Country.Jordan;
                      } else if (myfatoorahCountry == 'Oman') {
                        return Country.Oman;
                      } else if (myfatoorahCountry == 'SaudiArabia') {
                        return Country.SaudiArabia;
                      } else if (myfatoorahCountry == 'SaudiArabia') {
                        return Country.Qatar;
                      }
                      return Country.SaudiArabia;
                    }(),
                    successUrl: successUrl,
                    errorUrl: errorUrl,
                    invoiceAmount: double.parse(amount),
                    userDefinedField: orderID,
                    language: () {
                      if (myfatoorahLanguage == 'english') {
                        return ApiLanguage.English;
                      }
                      return ApiLanguage.Arabic;
                    }(),
                    token: token,
                  )
                : MyfatoorahRequest.live(
                    currencyIso: () {
                      if (myfatoorahCountry == 'Kuwait') {
                        return Country.Kuwait;
                      } else if (myfatoorahCountry == 'UAE') {
                        return Country.UAE;
                      } else if (myfatoorahCountry == 'Egypt') {
                        return Country.Egypt;
                      } else if (myfatoorahCountry == 'Bahrain') {
                        return Country.Bahrain;
                      } else if (myfatoorahCountry == 'Jordan') {
                        return Country.Jordan;
                      } else if (myfatoorahCountry == 'Oman') {
                        return Country.Oman;
                      } else if (myfatoorahCountry == 'SaudiArabia') {
                        return Country.SaudiArabia;
                      } else if (myfatoorahCountry == 'SaudiArabia') {
                        return Country.Qatar;
                      }
                      return Country.SaudiArabia;
                    }(),
                    successUrl: successUrl,
                    userDefinedField: orderID,
                    errorUrl: errorUrl,
                    invoiceAmount: double.parse(amount),
                    language: () {
                      if (myfatoorahLanguage == 'english') {
                        return ApiLanguage.English;
                      }
                      return ApiLanguage.Arabic;
                    }(),
                    token: token,
                  ),
          );
          context.read<CartProvider>().setProgress(false);
          print("response status*****${response.status}");
          if (response.isSuccess) {
            context.read<CartProvider>().setProgress(true);
            final paymentIdProvider =
                Provider.of<PaymentIdProvider>(context, listen: false);
            paymentIdProvider.setPaymentId(response.paymentId!);
            await updateOrderStatus(orderID: orderID, status: PLACED);
            addTransaction(
              response.paymentId,
              orderID,
              SUCCESS,
              msg,
              true,
            );
          }
          if (response.isNothing) {
            setSnackbar(response.status.toString(), context);
            deleteOrders(orderID);
          }
          if (response.isError) {
            setSnackbar(response.status.toString(), context);
            deleteOrders(orderID);
          }
        } on TimeoutException catch (_) {
          context.read<CartProvider>().setProgress(false);
          setSnackbar(getTranslated(context, 'somethingMSg')!, context);
        }
      } else {
        if (mounted) {
          setState(
            () {
              _isNetworkAvailable = false;
            },
          );
        }
      }
    }

    stripePayment(
      String? tranId,
      String orderID,
      String? status,
      String? msg,
      bool redirect,
    ) async {
      context.read<CartProvider>().setProgress(true);
      final response = await StripeService.payWithPaymentSheet(
        amount: ((usedBalance > 0
                        ? totalPrice
                        : isStorePickUp == "false"
                            ? (totalPrice + deliveryCharge)
                            : totalPrice)
                    .toInt() *
                100)
            .toString(),
        currency: stripeCurCode,
        from: "order",
        context: context,
        awaitedOrderId: orderID,
      );
      print("resonse status***${response.status}");
      if (response.message == "Transaction successful") {
        await updateOrderStatus(orderID: orderID, status: PLACED);
        addTransaction(
          stripePayId,
          orderID,
          response.status == 'succeeded' ? SUCCESS : WAITING,
          msg,
          true,
        );
      } else if (response.status == 'pending' || response.status == "captured") {
        await updateOrderStatus(orderID: orderID, status: WAITING);
        addTransaction(
          stripePayId,
          orderID,
          response.status == 'succeeded' ? PLACED : WAITING,
          msg,
          true,
        );
      } else {
        deleteOrders(orderID);
        if (mounted) {
          setState(() {
            _placeOrder = true;
          });
        }
        context.read<CartProvider>().setProgress(false);
      }
      setSnackbar(response.message!, context);
    }

    // Make sure to declare and initialize the mobileController in your State:
// TextEditingController mobileController = TextEditingController();
// In initState():
// mobileController.text = context.read<UserProvider>().mobile ?? '';

Widget address() {
  final selectedMosque = context.read<MosqueProvider>().selectedMosque;

  return Card(
    elevation: 1,
    child: Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on),
              const SizedBox(width: 8),
              Text(
                getTranslated(context, 'SHIPPING_DETAIL') ?? 'Delivery Address',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.fontColor,
                ),
              ),
            ],
          ),
          const Divider(),

          // If a Mosque is already chosen, display its info + "Change".
          if (selectedMosque != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          selectedMosque.name.isNotEmpty == true
                              ? selectedMosque.name
                              : "Mosque at (${selectedMosque.latitude}, ${selectedMosque.longitude})",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                      InkWell(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Text(
                            getTranslated(context, 'CHANGE') ?? 'CHANGE',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primarytheme,
                            ),
                          ),
                        ),
                        onTap: () async {
                          // When "Change" is tapped, open QatarMosques in checkout mode:
                          final mosque = await Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => BlocProvider<FetchMosquesCubit>(
      create: (context) => FetchMosquesCubit()..fetchMosques(),
      child: QatarMosques(isFromCheckout: true),
    ),
  ),
);

                          if (mosque != null && mosque is MosqueModel) {
                            context.read<MosqueProvider>().setSelectedMosque(mosque);
                            checkDeliverable(2);
                          }
                        },
                      ),
                    ],
                  ),
                  Text(
                    selectedMosque.address?.isNotEmpty == true
                        ? selectedMosque.address!
                        : "Mosque at (${selectedMosque.latitude}, ${selectedMosque.longitude})",
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                          color: Theme.of(context).colorScheme.lightBlack,
                        ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    "Lat: ${selectedMosque.latitude}, Lng: ${selectedMosque.longitude}",
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                          color: Theme.of(context).colorScheme.lightBlack,
                        ),
                  ),
                ],
              ),
            )
          else
            // If no mosque selected, let user pick one
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
  Text(
    getTranslated(context, 'NO_MOSQUE_SELECTED') ?? 'No Mosque Selected',
    style: TextStyle(
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.primary,
    ),
  ),
  const SizedBox(height: 4),
  Text(
    getTranslated(context, 'MOSQUE_NOT_SELECTED_MSG') 
      ?? 'If you do not select a mosque, your product will be delivered to our designated Most Needed Mosque in Qatar.',
    style: Theme.of(context).textTheme.bodySmall!.copyWith(
      color: Theme.of(context).colorScheme.lightBlack,
    ),
  ),


                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () async {
                      final mosque = await Navigator.pushNamed(
                        context,
                        Routers.qatarMosquesScreen,
                        arguments: true, // or pass a param that indicates checkout
                      );
                      if (mosque != null && mosque is MosqueModel) {
                        context.read<MosqueProvider>().setSelectedMosque(mosque);
                        checkDeliverable(2);
                      }
                    },
                    child: Text(
                      getTranslated(context, 'SELECT_MOSQUE') ?? "Select Mosque",
                    ),
                  ),
                ],
              ),
            ),
 const SizedBox(height: 16),
          // Mobile Number Input Container added below the address section:
         TextField(
            controller: mobileController,
            keyboardType: Platform.isIOS
                ? TextInputType.number
                : TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textInputAction: TextInputAction.done,
            onEditingComplete: () => FocusScope.of(context).unfocus(),
            style: TextStyle(
              fontSize: 15,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black,
            ),
            decoration: InputDecoration(
              labelText: getTranslated(context, 'MOBILE_NUMBER_LABEL') ?? 'Mobile Number',
              labelStyle: TextStyle(
                fontSize: 14,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white70
                    : Colors.grey[800],
              ),
              hintText: getTranslated(context, 'ENTER_MOBILE_NUMBER') ?? 'Enter mobile number',
              hintStyle: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white54
                    : Colors.grey[500],
              ),
              prefixIcon: Icon(
                Icons.phone_android,
                color: Theme.of(context).colorScheme.primary,
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.check),
                onPressed: () {
                  FocusScope.of(context).unfocus(); // Unfocus manually
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ],
      ),
    ),
  );
}







    // Payment section now directly shows SkipCash as the only option
    // along with date & time selection widgets.
    payment() {
      return Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.payment),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8.0),
                    child: Text(
                      getTranslated(context, 'PAYMENT')!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.fontColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(getTranslated(context, 'SKIPCASH_LBL')!),
                ],
              ),
              const Divider(),
              if (_isTimeSlotLoading)
                const SizedBox(height: 50, child: Center(child: CircularProgressIndicator()))
              else if (isTimeSlot == true)
                Column(
                  children: [
                    SizedBox(
                      height: 100,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: int.parse(allowDay ?? '0'),
                        itemBuilder: (context, index) => dateCell(index),
                      ),
                    ),
                    const Divider(),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: timeModel.length,
                      itemBuilder: (context, index) => timeSlotItem(index),
                    ),
                  ],
                )
              else
                const SizedBox.shrink(),
            ],
          ),
        ),
      );
    }

    cartItems(List<SectionModel> cartList) {
      return ListView.builder(
        shrinkWrap: true,
        itemCount: cartList.length,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, index) {
          return cartItem(index, cartList);
        },
      );
    }

    orderSummary(List<SectionModel> cartList) {
      return Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "${getTranslated(context, 'ORDER_SUMMARY')!} (${cartList.length} items)",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.fontColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    getTranslated(context, 'SUBTOTAL')!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.lightBlack2,
                    ),
                  ),
                  Text(
  "${currencySymbol(context.read<CurrencyProvider>().selectedCurrency)} ${context.read<CurrencyProvider>().convertPrice(originalPrice).toStringAsFixed(2)}",
  style: TextStyle(
    color: Theme.of(context).colorScheme.fontColor,
    fontWeight: FontWeight.bold,
  ),
),

                ],
              ),
              if (cartList[0].productList![0].productType != 'digital_product')
                if (isStorePickUp == "false")
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        getTranslated(context, 'DELIVERY_CHARGE')!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.lightBlack2,
                        ),
                      ),
                     buildConvertedPrice(
  context,
  deliveryCharge,
  style: Theme.of(context).textTheme.titleSmall!.copyWith(
    color: Theme.of(context).colorScheme.fontColor,
    fontWeight: FontWeight.bold,
  ),
)

                    ],
                  ),
              if (IS_SHIPROCKET_ON == "1" &&
                  isStorePickUp == "false" &&
                  shipRocketDeliverableDate != "" &&
                  !isLocalDelCharge!)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      getTranslated(context, 'DELIVERY_DAY_LBL')!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.lightBlack2,
                      ),
                    ),
                    Text(
                      shipRocketDeliverableDate,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.fontColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              if (isPromoValid!)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      getTranslated(context, 'PROMO_CODE_DIS_LBL')!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.lightBlack2,
                      ),
                    ),
                    buildConvertedPrice(
  context,
  promoAmount,
  style: Theme.of(context).textTheme.titleMedium!.copyWith(
    color: Theme.of(context).colorScheme.fontColor,
    fontWeight: FontWeight.bold,
  ),
),

                  ],
                )
              else
                const SizedBox.shrink(),
              if (isUseWallet!)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      getTranslated(context, 'WALLET_BAL')!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.lightBlack2,
                      ),
                    ),
                    buildConvertedPrice(
  context,
  usedBalance,
  style: Theme.of(context).textTheme.titleMedium!.copyWith(
    color: Theme.of(context).colorScheme.fontColor,
    fontWeight: FontWeight.bold,
  ),
),

                  ],
                )
              else
                const SizedBox.shrink(),
            ],
          ),
        ),
      );
    }

    Future<void> validatePromo(bool check) async {
      _isNetworkAvailable = await isNetworkAvailable();
      if (_isNetworkAvailable) {
        try {
          context.read<CartProvider>().setProgress(true);
          if (check) {
            if (mounted) checkoutState?.call(() {});
          }
          setState(() {});
          final parameter = {
            USER_ID: context.read<UserProvider>().userId,
            PROMOCODE: promoCodeController.text,
            FINAL_TOTAL: originalPrice.toString(),
          };
          apiBaseHelper.postAPICall(validatePromoApi, parameter).then(
            (getdata) {
              final bool error = getdata["error"];
              final String? msg = getdata["message"];
              if (!error) {
                final data = getdata["data"][0];
                totalPrice = double.parse(data["final_total"]);
                promoAmount = double.parse(data["final_discount"]);
                promocode = data["promo_code"];
                isPromoValid = true;
                isPromoLen = false;
                setSnackbar(getTranslated(context, 'PROMO_SUCCESS')!, context);
              } else {
                isPromoValid = false;
                promoAmount = 0;
                promocode = null;
                promoCodeController.clear();
                isPromoLen = false;
                final data = getdata["data"];
                totalPrice = double.parse(data["final_total"]);
                setSnackbar(msg!, context);
              }
              if (isUseWallet!) {
                remWalBal = 0;
                paymentMethod = null;
                usedBalance = 0;
                isUseWallet = false;
                isPayLayShow = true;
                selectedMethod = null;
                context.read<CartProvider>().setProgress(false);
                if (mounted && check) checkoutState?.call(() {});
                setState(() {});
              } else {
                if (mounted && check) checkoutState?.call(() {});
                setState(() {});
                context.read<CartProvider>().setProgress(false);
              }
            },
            onError: (error) {
              setSnackbar(error.toString(), context);
            },
          );
        } on TimeoutException catch (_) {
          context.read<CartProvider>().setProgress(false);
          if (mounted && check) checkoutState?.call(() {});
          setState(() {});
          setSnackbar(getTranslated(context, 'somethingMSg')!, context);
        }
      } else {
        _isNetworkAvailable = false;
        if (mounted && check) checkoutState!(() {});
        setState(() {});
      }
    }

    Future<void> flutterwavePayment(
      String? tranId,
      String orderID,
      String? status,
      String? msg,
      bool redirect,
    ) async {
      _isNetworkAvailable = await isNetworkAvailable();
      if (_isNetworkAvailable) {
        try {
          context.read<CartProvider>().setProgress(true);
          final parameter = {
            AMOUNT: usedBalance > 0
                ? totalPrice.toString()
                : isStorePickUp == "false"
                    ? (totalPrice + deliveryCharge).toString()
                    : totalPrice.toString(),
            USER_ID: context.read<UserProvider>().userId,
            ORDER_ID: orderID,
          };
          apiBaseHelper.postAPICall(flutterwaveApi, parameter).then(
            (getdata) {
              final bool error = getdata["error"];
              final String? msg = getdata["message"];
              if (!error) {
                final data = getdata["link"];
                Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (BuildContext context) => PaypalWebview(
                      url: data,
                      from: "order",
                      orderId: orderID,
                    ),
                  ),
                ).then(
                  (value) {
                    if (value == 'true') {
                      checkoutState?.call(
                        () {
                          _placeOrder = true;
                        },
                      );
                    } else {
                      deleteOrders(orderID);
                    }
                  },
                );
              } else {
                setSnackbar(msg!, context);
              }
              context.read<CartProvider>().setProgress(false);
            },
            onError: (error) {
              setSnackbar(error.toString(), context);
            },
          );
        } on TimeoutException catch (_) {
          context.read<CartProvider>().setProgress(false);
          setSnackbar(getTranslated(context, 'somethingMSg')!, context);
        }
      } else {
        if (mounted) {
          checkoutState?.call(() {
            _isNetworkAvailable = false;
          });
        }
      }
    }

    Future<void> checkDeliverable(
  int from, {
  bool showErrorMessage = true,
}) async {
  _isNetworkAvailable = await isNetworkAvailable();
  if (_isNetworkAvailable) {
    try {
      // Show progress indicator.
      context.read<CartProvider>().setProgress(true);
      final parameter = {
        USER_ID: context.read<UserProvider>().userId,
        ADD_ID: (selectedMosque?.id.isNotEmpty == true)
            ? selectedMosque!.id
            : "999",
      };
      await apiBaseHelper.postAPICall(checkCartDelApi, parameter).then(
        (getdata) {
          // Turn off progress.
          context.read<CartProvider>().setProgress(false);
          // No matter what the API returns, force deliverable to true.
          checkoutState?.call(() {
            deliverable = true;
            _placeOrder = true;
          });
          // Optionally, you can print the data for debugging.
          print("API check deliverable data: ${getdata['data']}");
          // Optionally, still call getShipRocketDeliveryCharge if you need shipping charge calculation.
          // getShipRocketDeliveryCharge("1", from);
        },
        onError: (error) {
          if (showErrorMessage) {
            setSnackbar(error.toString(), context);
          }
        },
      );
    } on TimeoutException catch (_) {
      if (showErrorMessage) {
        setSnackbar(getTranslated(context, 'somethingMSg')!, context);
      }
    }
  } else {
    if (mounted) {
      setState(() {
        _isNetworkAvailable = false;
      });
    }
  }
}



  attachPrescriptionImages(List<SectionModel> cartList) {
      bool isAttachmentRequired = false;
      for (int i = 0; i < cartList.length; i++) {
        if (cartList[i].productList![0].is_attchachment_required == "1") {
          isAttachmentRequired = true;
        }
      }
      return ALLOW_ATT_MEDIA == "1" && isAttachmentRequired
          ? Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          getTranslated(context, 'ADD_ATT_REQ')!,
                          style: Theme.of(context).textTheme.titleSmall!.copyWith(
                                color: Theme.of(context).colorScheme.lightBlack,
                              ),
                        ),
                        SizedBox(
                          height: 30,
                          child: IconButton(
                            icon: Icon(
                              Icons.add_photo_alternate,
                              color: Theme.of(context).colorScheme.primarytheme,
                              size: 20.0,
                            ),
                            onPressed: () {
                              _imgFromGallery(
                                context,
                                onFilePick: (pickedFiles) {
                                  checkoutState?.call(() {
                                    prescriptionImages = pickedFiles;
                                  });
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsetsDirectional.only(
                        start: 20.0,
                        end: 20.0,
                        top: 5,
                      ),
                      height: prescriptionImages.isNotEmpty ? 180 : 0,
                      child: Row(
                        children: [
                          Expanded(
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: prescriptionImages.length,
                              scrollDirection: Axis.horizontal,
                              itemBuilder: (context, i) {
                                return InkWell(
                                  child: Stack(
                                    alignment: AlignmentDirectional.topEnd,
                                    children: [
                                      Image.file(
                                        prescriptionImages[i],
                                        width: 180,
                                        height: 180,
                                      ),
                                      Container(
                                        color:
                                            Theme.of(context).colorScheme.black26,
                                        child: const Icon(
                                          Icons.clear,
                                          size: 15,
                                        ),
                                      ),
                                    ],
                                  ),
                                  onTap: () {
                                    checkoutState?.call(() {
                                      prescriptionImages.removeAt(i);
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox.shrink();
    }

    //─────────────────────────────────────────────
    // Fetch delivery date and time slots (copied from old Payment screen)
    Future<void> _getdateTime() async {
      _isNetworkAvailable = await isNetworkAvailable();
      if (_isNetworkAvailable) {
        timeSlotList.clear();
        try {
          final parameter = {
            TYPE: PAYMENT_METHOD,
            USER_ID: context.read<UserProvider>().userId,
          };
          apiBaseHelper.postAPICall(getSettingApi, parameter).then(
            (getdata) async {
              final bool error = getdata["error"];
              if (!error) {
                final data = getdata["data"];
                final timeSlot = data["time_slot_config"];
                allowDay = timeSlot["allowed_days"];
                isTimeSlot =
                    timeSlot["is_time_slots_enabled"] == "1" ? true : false;
                startingDate = timeSlot["starting_date"];
                final timeSlots = data["time_slots"];
                timeSlotList = (timeSlots as List)
                    .map((ts) => Model.fromTimeSlot(ts))
                    .toList();

                // Default to first available date/time when none selected
                if ((selDate == null || selDate!.isEmpty) && startingDate != null) {
                  final DateTime first = DateTime.parse(startingDate!);
                  selDate = DateFormat('yyyy-MM-dd').format(first);
                  selectedDate = 0;
                }
                if ((selTime == null || selTime!.isEmpty) && timeSlotList.isNotEmpty) {
                  selTime = timeSlotList[0].name;
                  selectedTime = 0;
                }
              }
              if (mounted) {
                checkoutState?.call(() {});
                setState(() {
                  _isTimeSlotLoading = false;
                });
              }
            },
            onError: (error) {
              setSnackbar(error.toString(), context);
            },
          );
        } on TimeoutException catch (_) {
          setSnackbar(getTranslated(context, 'somethingMSg')!, context);
        }
      } else {
        if (mounted) {
          setState(() {
            _isNetworkAvailable = false;
          });
        }
      }
    }

    // Date cell widget used for selecting delivery date
    Widget dateCell(int index) {
      final DateTime today = DateTime.parse(startingDate!);
      return InkWell(
        child: Container(
          width: 65,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: selectedDate == index
                ? Theme.of(context).colorScheme.primarytheme
                : null,
          ),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateFormat('EEE').format(today.add(Duration(days: index))),
                style: TextStyle(
                  color: selectedDate == index
                      ? Theme.of(context).colorScheme.white
                      : Theme.of(context).colorScheme.lightBlack2,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(5.0),
                child: Text(
                  DateFormat('dd').format(today.add(Duration(days: index))),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: selectedDate == index
                        ? Theme.of(context).colorScheme.white
                        : Theme.of(context).colorScheme.lightBlack2,
                  ),
                ),
              ),
              Text(
                DateFormat('MMM').format(today.add(Duration(days: index))),
                style: TextStyle(
                  color: selectedDate == index
                      ? Theme.of(context).colorScheme.white
                      : Theme.of(context).colorScheme.lightBlack2,
                ),
              ),
            ],
          ),
        ),
        onTap: () {
          final DateTime date = today.add(Duration(days: index));
          if (mounted) {
            checkoutState?.call(() {
              selectedDate = index;
              selectedTime = null;
              selTime = null;
              selDate = DateFormat('yyyy-MM-dd').format(date);
            });
          } else {
            selectedDate = index;
            selectedTime = null;
            selTime = null;
            selDate = DateFormat('yyyy-MM-dd').format(date);
          }
          timeModel.clear();
          final DateTime cur = DateTime.now();
          final DateTime tdDate = DateTime(cur.year, cur.month, cur.day);
          if (date == tdDate) {
            if (timeSlotList.isNotEmpty) {
              for (int i = 0; i < timeSlotList.length; i++) {
                final DateTime cur = DateTime.now();
                final String time = timeSlotList[i].lastTime!;
                final DateTime last = DateTime(
                  cur.year,
                  cur.month,
                  cur.day,
                  int.parse(time.split(':')[0]),
                  int.parse(time.split(':')[1]),
                  int.parse(time.split(':')[2]),
                );
                if (cur.isBefore(last)) {
                  timeModel.add(RadioModel(
                    isSelected: i == selectedTime ? true : false,
                    name: timeSlotList[i].name,
                    img: '',
                  ));
                }
              }
            }
          } else {
            if (timeSlotList.isNotEmpty) {
              for (int i = 0; i < timeSlotList.length; i++) {
                timeModel.add(RadioModel(
                  isSelected: i == selectedTime ? true : false,
                  name: timeSlotList[i].name,
                  img: '',
                ));
              }
            }
          }
          checkoutState?.call(() {});
        },
      );
    }

    // Time slot radio item
    Widget timeSlotItem(int index) {
      return InkWell(
        onTap: () {
          if (mounted) {
            checkoutState?.call(() {
              selectedTime = index;
              selTime = timeModel[selectedTime!].name;
              for (final element in timeModel) {
                element.isSelected = false;
              }
              timeModel[index].isSelected = true;
            });
          }
        },
        child: RadioItem(timeModel[index]),
      );
    }

  }
