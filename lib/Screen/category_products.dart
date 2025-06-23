import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../Model/MosqueModel.dart';
import '../Provider/MosqueProvider.dart';
import '../cubits/FetchMosquesCubit.dart';
import '../ui/widgets/AppBarWidget.dart';
import '../Helper/Session.dart';
import '../ui/widgets/product_list_content.dart';
import '../app/routes.dart';

class CategoryProducts extends StatefulWidget {
  final String id;
  final String title;
  const CategoryProducts({super.key, required this.id, required this.title});

  @override
  State<CategoryProducts> createState() => _CategoryProductsState();
}

class _CategoryProductsState extends State<CategoryProducts> {
  MosqueModel? _selectedMosque;

  @override
  void initState() {
    super.initState();
    context.read<FetchMosquesCubit>().fetchMosques();
    _selectedMosque = context.read<MosqueProvider>().selectedMosque;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: getAppBar(widget.title, context),
      body: Column(
        children: [
          
          Transform.translate(
            offset: const Offset(0, -4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              
            ),
          ),
          Expanded(
            child: ProductListContent(
              id: widget.id,
              tag: false,
              fromSeller: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final double fontSize;
  final double iconSize;
  final double verticalPadding;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.fontSize = 14,
    this.iconSize = 20,
    this.verticalPadding = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding:
              EdgeInsets.symmetric(vertical: verticalPadding, horizontal: 8),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary, size: iconSize),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: fontSize,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
