import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../themes/theme_extensions.dart';
import '../blocs/ble/ble_bloc.dart';
import '../blocs/ble/ble_event.dart';
import '../blocs/ble/ble_state.dart';
import '../widgets/no_etalon_dialog.dart';
import '../widgets/angle_range_dialog.dart';
import 'exercise_screen.dart';
import 'record_etalon_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  BleBloc? _bleBloc;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Сохраняем ссылку на BleBloc
    _bleBloc ??= context.read<BleBloc>();
  }

  @override
  void initState() {
    super.initState();
    // Останавливаем поток данных при входе на главный экран
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BleBloc>().add(BleStopDataStream());
    });
  }

  Widget _buildNavigationCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isDisabled = false,
  }) {
    final themeExt = Theme.of(context).extension<AppThemeExtension>()!;

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: isDisabled ? 0.6 : 1.0,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(isDisabled ? 0.1 : 0.3),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(
                icon,
                size: 40,
                color: color,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: themeExt.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: themeExt.textSecondaryColor,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: color,
              size: 24,
            ),
          ],
        ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeExt = Theme.of(context).extension<AppThemeExtension>()!;
    final gradient = themeExt.backgroundGradient;

    return Container(
      decoration: BoxDecoration(gradient: gradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            "Reflex",
            style: TextStyle(
              color: themeExt.textPrimaryColor,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
          actions: [
            // Settings button for angle borders
            BlocBuilder<BleBloc, BleState>(
              builder: (context, state) {
                return IconButton(
                  icon: Icon(Icons.settings, color: themeExt.primaryColor),
                  onPressed: () async {
                    final result = await showAngleRangeDialog(
                      context,
                      initialMinAngle: state.minAngleBorder,
                      initialMaxAngle: state.maxAngleBorder,
                    );
                    if (result != null) {
                      context.read<BleBloc>().add(
                        BleUpdateAngleBorders(
                          minAngle: result['minAngle']!,
                          maxAngle: result['maxAngle']!,
                        ),
                      );
                    }
                  },
                );
              },
            ),
            // Bluetooth button
            BlocBuilder<BleBloc, BleState>(
              builder: (context, state) {
                IconData icon;
                Color iconColor;
                switch (state.status) {
                  case BleConnectionStatus.connected:
                    icon = Icons.bluetooth_connected;
                    iconColor = themeExt.primaryColor;
                    break;
                  case BleConnectionStatus.scanning:
                    icon = Icons.bluetooth_searching;
                    iconColor = themeExt.primaryColor.withOpacity(0.6);
                    break;
                  case BleConnectionStatus.connecting:
                    icon = Icons.bluetooth;
                    iconColor = themeExt.primaryColor.withOpacity(0.6);
                    break;
                  case BleConnectionStatus.disconnected:
                  default:
                    icon = Icons.bluetooth_disabled;
                    iconColor = themeExt.textSecondaryColor;
                }

                return IconButton(
                  icon: Icon(icon, color: iconColor),
                  onPressed: () {
                    context.read<BleBloc>().add(BleRestartScan());
                  },
                );
              },
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 40),

              // Welcome text
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Добро пожаловать!',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: themeExt.textPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Выберите действие',
                      style: TextStyle(
                        fontSize: 16,
                        color: themeExt.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // Exercise card (with etalon check)
              BlocBuilder<BleBloc, BleState>(
                builder: (context, state) {
                  final hasEtalon = state.referenceSegments.isNotEmpty;
                  
                  return _buildNavigationCard(
                    context: context,
                    title: 'Начать упражнение',
                    subtitle: hasEtalon 
                        ? 'Тренировка с эталоном' 
                        : 'Требуется запись эталона',
                    icon: Icons.fitness_center,
                    color: themeExt.primaryColor,
                    isDisabled: !hasEtalon,
                    onTap: () async {
                      if (!hasEtalon) {
                        // Show dialog if no etalon
                        await showNoEtalonDialog(context);
                      } else {
                        // Navigate to exercise screen
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (newContext) => BlocProvider.value(
                              value: context.read<BleBloc>(),
                              child: const ExerciseScreen(),
                            ),
                          ),
                        );
                      }
                    },
                  );
                },
              ),

              // Record etalon card
              _buildNavigationCard(
                context: context,
                title: 'Записать эталон',
                subtitle: 'Создать новый эталон',
                icon: Icons.fiber_manual_record,
                color: themeExt.accentColor,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (newContext) => BlocProvider.value(
                        value: context.read<BleBloc>(),
                        child: const RecordEtalonScreen(),
                      ),
                    ),
                  );
                },
              ),

              const Spacer(),

              // Connection status
              BlocBuilder<BleBloc, BleState>(
                builder: (context, state) {
                  String statusText;
                  Color statusColor;

                  switch (state.status) {
                    case BleConnectionStatus.connected:
                      statusText = 'Подключено';
                      statusColor = themeExt.primaryColor;
                      break;
                    case BleConnectionStatus.scanning:
                      statusText = 'Поиск устройства...';
                      statusColor = themeExt.textSecondaryColor;
                      break;
                    case BleConnectionStatus.connecting:
                      statusText = 'Подключение...';
                      statusColor = themeExt.textSecondaryColor;
                      break;
                    case BleConnectionStatus.disconnected:
                    default:
                      statusText = 'Не подключено';
                      statusColor = themeExt.textSecondaryColor;
                  }

                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.circle,
                          size: 12,
                          color: statusColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
