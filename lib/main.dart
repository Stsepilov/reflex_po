import 'package:flutter/material.dart';
import 'package:reflex_po/themes/app_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'blocs/ble/ble_bloc.dart';
import 'blocs/ble/ble_event.dart';
import 'navigation/app_router.dart';

void main() {
  runApp(const ReFlex());
}

class ReFlex extends StatelessWidget {
  const ReFlex({super.key});

  @override
  Widget build(BuildContext context) {
    final router = buildAppRouter();
    return BlocProvider(
      create: (_) => BleBloc()..add(BleStartScan()),
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: appTheme(),
        routerConfig: router,
      ),
    );
  }
}
