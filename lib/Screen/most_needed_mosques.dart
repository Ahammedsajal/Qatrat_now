import 'package:flutter/material.dart';
import '../Model/MosqueModel.dart';
import '../Provider/MosqueProvider.dart';
import '../cubits/FetchMosquesCubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../ui/widgets/AppBarWidget.dart';
import 'package:customer/app/routes.dart';
import '../Helper/Session.dart';
import '../ui/widgets/product_list_content.dart';


// Define your color constants
const Color kPrimaryColor = Color(0xFF26897E);
const Color kSecondaryColor = Color(0xFF1EBAAA);
const Color kAccentColor = Color(0xFF247B88);

class MostNeededMosques extends StatefulWidget {
  const MostNeededMosques({super.key});

  @override
  _MostNeededMosquesState createState() => _MostNeededMosquesState();
}

class _MostNeededMosquesState extends State<MostNeededMosques> {
  MosqueModel? _selectedMosque;

  @override
  void initState() {
    super.initState();
    // Fetch mosques on init.
    context.read<FetchMosquesCubit>().fetchNeededMosques();
    _selectedMosque = context.read<MosqueProvider>().selectedMosque;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: getAppBar(
        getTranslated(context, 'MOST_NEEDED_MOSQUES') ?? 'Most Needed Mosques',
        context,
      ),
      body: Column(
        children: [
          // Mosque dropdown widget.
          Padding(
  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
  child: BlocBuilder<FetchMosquesCubit, FetchMosquesState>(
    builder: (context, state) {
      List<MosqueModel> mosques = [];
      String hintText = getTranslated(context, 'CHOOSE_MOSQUE') ?? "Choose from the list";
      bool isDisabled = false;

      if (state is FetchMosquesInProgress) {
        hintText = getTranslated(context, 'LOADING_MOSQUES') ?? "Loading mosques...";
        isDisabled = true;
      } else if (state is FetchMosquesSuccess) {
        mosques = state.mosques;
      } else if (state is FetchMosquesFail) {
        hintText = getTranslated(context, 'ERROR_LOADING_MOSQUES') ?? "Error loading mosques";
        isDisabled = true;
      }

      return DropdownButtonFormField<MosqueModel>(
        isExpanded: true,
        value: _selectedMosque,
          dropdownColor: Theme.of(context).cardColor, // clearly visible background

        items: mosques.map((mosque) {
  final isArabic = Localizations.localeOf(context).languageCode == "ar";

  final mosqueName = isArabic
      ? (mosque.nameAr?.isNotEmpty ?? false ? mosque.nameAr! : mosque.name)
      : mosque.name;

  final mosqueDisplay = "${mosque.id} - $mosqueName";

  return DropdownMenuItem<MosqueModel>(
    value: mosque,
    child: Text(
      mosqueDisplay,
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).textTheme.bodyMedium!.color,
      ),
    ),
  );
}).toList(),

        onChanged: isDisabled ? null : (MosqueModel? mosque) {
          if (mosque != null) {
            setState(() {
              _selectedMosque = mosque;
            });
            context.read<MosqueProvider>().setSelectedMosque(mosque);
          }
        },
        decoration: InputDecoration(
          labelText: getTranslated(context, 'SELECT_MOSQUE') ?? "Select a Mosque",
          labelStyle: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontSize: 14,
          ),
          hintText: hintText,
          filled: true,
          fillColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 1.0,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 2.0,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    },
  ),
),

// Action tiles for "Clear Mosque" and "Select from Map" in a compact layout.
Transform.translate(
  offset: const Offset(0, -4), // Pull upward by 4 pixels.
  child: Padding( // Pull upward slightly
  padding: const EdgeInsets.symmetric(horizontal: 12.0),
  child: Row(
    children: [
      Expanded(
        child: _ActionTile(
          icon: Icons.clear,
          title: getTranslated(context, 'CLEAR_MOSQUE') ?? "Clear Mosque",
          onTap: () {
            setState(() {
              _selectedMosque = null;
            });
            context.read<MosqueProvider>().clearSelectedMosque();
          },
          fontSize: 12,
          iconSize: 18,
          verticalPadding: 6,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _ActionTile(
          icon: Icons.map,
          title: getTranslated(context, 'SELECT_FROM_MAP') ?? "Select from Map",
          onTap: () {
            Navigator.pushNamed(context, Routers.qatarMosquesScreen);
          },
          fontSize: 12,
          iconSize: 18,
          verticalPadding: 6,
        ),
      ),
    ],
  ),
),),


          // Expanded product list content below the dropdown and action tiles.
          const Expanded(
            child: ProductListContent(
              id: "111",
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
          padding: EdgeInsets.symmetric(vertical: verticalPadding, horizontal: 8),
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
