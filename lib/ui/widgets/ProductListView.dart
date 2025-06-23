import 'package:customer/app/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:provider/provider.dart';
import '../../Helper/Color.dart';
import '../../Helper/String.dart' hide currencySymbol;
import '../../Model/Section_Model.dart';
import '../styles/DesignConfig.dart';
import 'package:customer/app/curreny_converter.dart';

Widget productItemView(
    int index, List<Product> productList, BuildContext context, String from) {
  if (index >= productList.length) return const SizedBox.shrink();

  final product = productList[index]; 
  String? offPer;

  double basePrice = double.parse(product.prVarientList![0].disPrice!);
  if (basePrice == 0) {
    basePrice = double.parse(product.prVarientList![0].price!);
  } else {
    final original = double.parse(product.prVarientList![0].price!);
    final offAmt = original - basePrice;
    offPer = ((offAmt * 100) / original).toStringAsFixed(2);
  }

  final double width = deviceWidth! * 0.45;

  return SizedBox(
    height: 255,
    width: width,
    child: Card(
      elevation: 0.2,
      margin: const EdgeInsetsDirectional.only(bottom: 5, end: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () {
          currentHero = from;
          Navigator.pushNamed(
            context,
            Routers.productDetails,
            arguments: {
              "id": product.id!,
              "secPos": 0,
              "index": index,
              "list": true,
            },
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.bottomRight,
                clipBehavior: Clip.none,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: 8.0),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(5),
                        topRight: Radius.circular(5),
                      ),
                      child: Hero(
                        tag: "$from$index${product.id}0",
                        child: networkImageCommon(
                          product.image!,
                          double.maxFinite,
                          false,
                          height: double.maxFinite,
                          width: double.maxFinite,
                        ),
                      ),
                    ),
                  ),
                  if (offPer != null)
                    Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        decoration: BoxDecoration(
                          color: colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        margin: const EdgeInsets.all(5),
                        child: Padding(
                          padding: const EdgeInsets.all(5.0),
                          child: Text(
                            "$offPer%",
                            style: const TextStyle(
                              color: colors.whiteTemp,
                              fontWeight: FontWeight.bold,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const Divider(height: 1),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 5.0, top: 5),
              child: Row(
                children: [
                  RatingBarIndicator(
                    rating: double.parse(product.rating!),
                    itemBuilder: (context, _) => const Icon(
                      Icons.star_rate_rounded,
                      color: Colors.amber,
                    ),
                    unratedColor: Colors.grey.withOpacity(0.5),
                    itemSize: 12.0,
                  ),
                  Text(
                    " (${product.noOfRating!})",
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(
                  start: 5.0, top: 5, bottom: 5),
              child: Text(
                product.name!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.fontColor,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Price with currency conversion listener
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 5.0),
              child: Consumer<CurrencyProvider>(
                builder: (ctx, currencyProvider, _) {
                  final symbol = currencySymbol(
                      currencyProvider.selectedCurrency);
                  final convertedPrice =
                      currencyProvider.convertPrice(basePrice);
                  return Row(
                    children: [
                      Text(
                        '$symbol ${convertedPrice.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: Theme.of(ctx).colorScheme.fontColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (double.parse(
                              product.prVarientList![0].disPrice!) !=
                          0)
                        Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: Text(
                            '$symbol ${currencyProvider.convertPrice(double.parse(product.prVarientList![0].price!)).toStringAsFixed(2)}',
                            style: Theme.of(ctx)
                                .textTheme
                                .labelSmall!
                                .copyWith(
                                  decoration: TextDecoration.lineThrough,
                                ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}