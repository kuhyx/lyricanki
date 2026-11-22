import 'package:kuhy_credit/kuhy_credit.dart';
import 'package:lyricanki/screens/home_status.dart';
import 'package:material_ui/material_ui.dart';

/// The home screen's app bar: status glyph, sync, pack, and the kuhy credit.
class HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Creates the bar. A null callback disables its button.
  const HomeAppBar({
    required this.status,
    required this.onSync,
    required this.onOpenPack,
    super.key,
  });

  /// The last sync or export outcome; hidden when null.
  final HomeStatus? status;

  /// Runs a history sync; null while a deck is being built.
  final VoidCallback? onSync;

  /// Opens the dictionary pack screen.
  final VoidCallback onOpenPack;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      actions: <Widget>[
        if (status case final shown?) HomeStatusGlyph(status: shown),
        IconButton(
          tooltip: 'Sync',
          icon: const Icon(Icons.sync, semanticLabel: 'Sync history'),
          onPressed: onSync,
        ),
        IconButton(
          tooltip: 'Dictionary',
          icon: const Icon(
            Icons.storage_outlined,
            semanticLabel: 'Dictionary pack',
          ),
          onPressed: onOpenPack,
        ),
        const Padding(
          padding: EdgeInsets.only(right: 12),
          child: KuhyCredit(size: 32, below: true),
        ),
      ],
    );
  }
}
