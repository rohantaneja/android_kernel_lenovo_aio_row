
include $(srctree)/drivers/misc/mediatek/Makefile.custom
ifneq ($(CONFIG_MTK_CUST_LEDS),y)
obj-$(CONFIG_MTK_LEDS) += mt65xx/
else
obj-$(CONFIG_MTK_CUST_LEDS) += mt6752/
endif

