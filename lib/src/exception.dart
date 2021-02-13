// Copyright (c) 2020, dolphinxx <bravedolphinxx@gmail.com>. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

class InterruptedError extends Error {
  /// Where this Error is thrown
  final String location;
  @override
  StackTrace stackTrace;

  InterruptedError(this.location, {StackTrace stackTrace});
}
