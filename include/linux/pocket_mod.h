#ifndef _LINUX_POCKET_MOD_H
#define _LINUX_POCKET_MOD_H

extern int is_screen_on;

int epl2182_pocket_detection_check(void);

int device_is_pocketed(void);

#endif //_LINUX_POCKET_MOD_H
