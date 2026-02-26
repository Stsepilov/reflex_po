import 'dart:math';

/// PCHIP (Piecewise Cubic Hermite Interpolating Polynomial)
/// Реализация shape-preserving (Fritsch–Carlson).
class Pchip {
  final List<double> x;
  final List<double> y;
  late final List<double> d;

  Pchip(this.x, this.y) {
    if (x.length != y.length) {
      throw ArgumentError('x и y должны быть одной длины');
    }
    if (x.length < 2) {
      throw ArgumentError('Нужно минимум 2 точки для интерполяции');
    }
    for (int i = 0; i < x.length - 1; i++) {
      if (!(x[i] < x[i + 1])) {
        throw ArgumentError('x должен быть строго возрастающим');
      }
    }
    d = _computeDerivatives(x, y);
  }

  static List<double> _computeDerivatives(List<double> x, List<double> y) {
    final int n = x.length;
    final List<double> h = List.filled(n - 1, 0.0);
    final List<double> delta = List.filled(n - 1, 0.0);

    for (int i = 0; i < n - 1; i++) {
      h[i] = x[i + 1] - x[i];
      delta[i] = (y[i + 1] - y[i]) / h[i];
    }

    final List<double> d = List.filled(n, 0.0);
    if (n == 2) {
      d[0] = delta[0];
      d[1] = delta[0];
      return d;
    }

    for (int i = 1; i < n - 1; i++) {
      final double d1 = delta[i - 1];
      final double d2 = delta[i];
      if (d1 == 0.0 || d2 == 0.0 || (d1 > 0) != (d2 > 0)) {
        d[i] = 0.0;
      } else {
        final double w1 = 2 * h[i] + h[i - 1];
        final double w2 = h[i] + 2 * h[i - 1];
        d[i] = (w1 + w2) / (w1 / d1 + w2 / d2);
      }
    }

    d[0] = _pchipEndpointSlope(h[0], h[1], delta[0], delta[1]);
    d[n - 1] =
        _pchipEndpointSlope(h[n - 2], h[n - 3], delta[n - 2], delta[n - 3]);
    return d;
  }

  static double _pchipEndpointSlope(
      double h0, double h1, double del0, double del1) {
    double d = ((2 * h0 + h1) * del0 - h0 * del1) / (h0 + h1);
    if ((d > 0) != (del0 > 0)) {
      d = 0.0;
    } else {
      if ((del0 > 0) != (del1 > 0) && d.abs() > 3 * del0.abs()) {
        d = 3 * del0;
      }
      if (d.abs() > 3 * del0.abs()) {
        d = 3 * del0;
      }
    }
    return d;
  }

  double eval(double xq) {
    if (xq <= x.first) return y.first;
    if (xq >= x.last) return y.last;

    final int k = _findInterval(x, xq);
    final double x0 = x[k];
    final double x1 = x[k + 1];
    final double y0 = y[k];
    final double y1 = y[k + 1];
    final double d0 = d[k];
    final double d1 = d[k + 1];

    final double h = x1 - x0;
    final double t = (xq - x0) / h;

    final double h00 = (2 * t * t * t - 3 * t * t + 1);
    final double h10 = (t * t * t - 2 * t * t + t);
    final double h01 = (-2 * t * t * t + 3 * t * t);
    final double h11 = (t * t * t - t * t);

    return h00 * y0 + h10 * h * d0 + h01 * y1 + h11 * h * d1;
  }

  List<double> resample(List<double> xGrid) => xGrid.map(eval).toList();

  static int _findInterval(List<double> x, double xq) {
    int lo = 0;
    int hi = x.length - 2;
    while (lo <= hi) {
      final int mid = (lo + hi) >> 1;
      if (xq < x[mid]) {
        hi = mid - 1;
      } else if (xq > x[mid + 1]) {
        lo = mid + 1;
      } else {
        return mid;
      }
    }
    return max(0, min(x.length - 2, lo));
  }
}
