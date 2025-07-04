import 'package:customer/Helper/Color.dart';
import 'package:customer/Model/Section_Model.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../app/routes.dart';
import '../ui/styles/DesignConfig.dart';
import '../ui/widgets/AppBarWidget.dart';
import '../utils/blured_router.dart';

class SubCategoryScreen extends StatelessWidget {
  final List<Product>? subList;
  final String title;
  final String? maxDis;
  final String? minDis;
  static route(RouteSettings settings) {
    final Map? arguments = settings.arguments as Map?;
    return BlurredRouter(
      builder: (context) {
        return SubCategoryScreen(
          title: arguments?['title'],
          minDis: arguments?['minDis'],
          maxDis: arguments?['maxDis'],
          subList: arguments?['subList'],
        );
      },
    );
  }

  const SubCategoryScreen({
    super.key,
    this.subList,
    required this.title,
    this.maxDis,
    this.minDis,
  });
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: getAppBar(title, context),
      body: GridView.count(
          padding: const EdgeInsets.all(20),
          crossAxisCount: 3,
          shrinkWrap: true,
          childAspectRatio: .75,
          children: List.generate(
            subList!.length,
            (index) {
              return subCatItem(index, context);
            },
          ),),
    );
  }

  subCatItem(int index, BuildContext context) {
    return InkWell(
      child: Column(
        children: <Widget>[
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(10.0),
                  child: networkImageCommon(subList![index].image!, 50, false),),
            ),
          ),
          Text(
            "${capitalize(subList![index].name!.toLowerCase())}\n",
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall!.copyWith(
                color: Theme.of(context).colorScheme.fontColor, fontSize: 14,),
          ),
        ],
      ),
      onTap: () {
        if (subList![index].subList == null ||
            subList![index].subList!.isEmpty) {
          Navigator.pushNamed(context, Routers.categoryProductsScreen, arguments: {
            "name": subList![index].name,
            "id": subList![index].id,
          },);
        } else {
          Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (context) => SubCategoryScreen(
                  subList: subList![index].subList,
                  title: subList![index].name!.toUpperCase(),
                  maxDis: maxDis,
                  minDis: minDis,
                ),
              ),);
        }
      },
    );
  }
}
