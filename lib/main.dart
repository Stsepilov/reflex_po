import 'package:flutter/material.dart';
import 'package:reflex_po/ui/home_page.dart';
import 'package:reflex_po/themes/app_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'blocs/ble/ble_bloc.dart';
import 'blocs/ble/ble_event.dart';

void main() {
  runApp(const ReFlex());
}

class ReFlex extends StatelessWidget {
  const ReFlex({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      home: BlocProvider(
        create: (_) => BleBloc()..add(BleStartScan()),
        child: HomePage(),
      ),
    );
  }
}
