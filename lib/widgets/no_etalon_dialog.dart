import 'package:flutter/material.dart';
import '../themes/theme_extensions.dart';

class NoEtalonDialog extends StatelessWidget {
  const NoEtalonDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final themeExt = Theme.of(context).extension<AppThemeExtension>()!;

    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      icon: Icon(
        Icons.warning_amber_rounded,
        color: themeExt.accentColor,
        size: 64,
      ),
      title: Text(
        'Эталон не записан',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: themeExt.textPrimaryColor,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Для выполнения упражнения необходимо сначала записать эталон движения.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: themeExt.textSecondaryColor,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Вернитесь на главный экран и выберите "Записать эталон".',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: themeExt.textPrimaryColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: themeExt.primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            minimumSize: const Size(double.infinity, 48),
          ),
          child: const Text('Понятно'),
        ),
      ],
    );
  }
}

/// Helper function to show the dialog
Future<void> showNoEtalonDialog(BuildContext context) async {
  return await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const NoEtalonDialog(),
  );
}
