// Copyright (c) 2026, the quick_blue authors.
// Use of this source code is governed by the BSD-3-Clause license.

#import <dispatch/dispatch.h>
#import "quick_blue_dispatch.h"

void *quick_blue_main_queue(void) {
  return (__bridge void *)dispatch_get_main_queue();
}
