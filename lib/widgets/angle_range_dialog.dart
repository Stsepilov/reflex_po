import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../themes/theme_extensions.dart';

class AngleRangeDialog extends StatefulWidget {
  final int? initialMinAngle;
  final int? initialMaxAngle;
  
  const AngleRangeDialog({
    super.key,
    this.initialMinAngle,
    this.initialMaxAngle,
  });

  @override
  State<AngleRangeDialog> createState() => _AngleRangeDialogState();
}

class _AngleRangeDialogState extends State<AngleRangeDialog> {
  late final TextEditingController _minController;
  late final TextEditingController _maxController;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _minController = TextEditingController(
      text: (widget.initialMinAngle ?? 0).toString(),
    );
    _maxController = TextEditingController(
      text: (widget.initialMaxAngle ?? 180).toString(),
    );
  }

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeExt = Theme.of(context).extension<AppThemeExtension>()!;

    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: Text(
        'Диапазон углов',
        style: TextStyle(
          color: themeExt.textPrimaryColor,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Укажите границы углов для упражнения.\nЗапись начнётся с максимального угла (разгибание) и завершится возвратом к нему.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: themeExt.textSecondaryColor,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            // Min angle input
            TextFormField(
              controller: _minController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: InputDecoration(
                labelText: 'Минимальный угол (°)',
                labelStyle: TextStyle(color: themeExt.textSecondaryColor),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: themeExt.primaryColor, width: 2),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Введите минимальный угол';
                }
                final min = int.tryParse(value);
                if (min == null) {
                  return 'Введите корректное число';
                }
                if (min < 0 || min > 180) {
                  return 'Угол должен быть от 0 до 180';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            // Max angle input
            TextFormField(
              controller: _maxController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: InputDecoration(
                labelText: 'Максимальный угол (°)',
                labelStyle: TextStyle(color: themeExt.textSecondaryColor),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: themeExt.primaryColor, width: 2),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Введите максимальный угол';
                }
                final max = int.tryParse(value);
                if (max == null) {
                  return 'Введите корректное число';
                }
                if (max < 0 || max > 180) {
                  return 'Угол должен быть от 0 до 180';
                }
                final min = int.tryParse(_minController.text);
                if (min != null && max <= min) {
                  return 'Максимум должен быть больше минимума';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Отмена',
            style: TextStyle(color: themeExt.textSecondaryColor),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final minAngle = int.parse(_minController.text);
              final maxAngle = int.parse(_maxController.text);
              Navigator.of(context).pop({
                'minAngle': minAngle,
                'maxAngle': maxAngle,
              });
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: themeExt.primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text('Начать запись'),
        ),
      ],
    );
  }
}

/// Helper function to show the dialog
Future<Map<String, int>?> showAngleRangeDialog(
  BuildContext context, {
  int? initialMinAngle,
  int? initialMaxAngle,
}) async {
  return await showDialog<Map<String, int>>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AngleRangeDialog(
      initialMinAngle: initialMinAngle,
      initialMaxAngle: initialMaxAngle,
    ),
  );
}
