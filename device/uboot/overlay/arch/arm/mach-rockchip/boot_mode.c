// SPDX-License-Identifier: GPL-2.0+
/*
 * (C) Copyright 2016 Rockchip Electronics Co., Ltd
 */

#include <adc.h>
#include <command.h>
#include <env.h>
#include <log.h>
#include <asm/io.h>
#include <asm/arch-rockchip/boot_mode.h>
#include <dm/device.h>
#include <dm/uclass.h>
#include <linux/printk.h>

/*
 * 长按复位键进入 MaskROM：boot-mode 寄存器地址兜底。
 * 设备实测 PMU_GRF 0xfdc20000 + 0x200(OS_REG0) = 0xfdc20200；
 * 写 BROM magic 0xEF08A53C 后复位进入 MaskROM。
 * 上游 Kconfig 的 ROCKCHIP_BOOT_MODE_REG 无默认值（未选=0），
 * 原版 "#if (==0)" 空桩会让整段逻辑静默失效，故必须兜底。
 */
#ifndef CONFIG_ROCKCHIP_BOOT_MODE_REG
#define CONFIG_ROCKCHIP_BOOT_MODE_REG 0xfdc20200
#endif

void set_back_to_bootrom_dnl_flag(void)
{
	writel(BOOT_BROM_DOWNLOAD, CONFIG_ROCKCHIP_BOOT_MODE_REG);
}

/*
 * detect download key status by adc, most rockchip
 * based boards use adc sample the download key status,
 * but there are also some use gpio. So it's better to
 * make this a weak function that can be override by
 * some special boards.
 */
#define KEY_DOWN_MIN_VAL	0
#define KEY_DOWN_MAX_VAL	30

#ifndef RK_DNL_ADC_CHAN
#define RK_DNL_ADC_CHAN		0
#endif

__weak int rockchip_dnl_key_pressed(void)
{
#if CONFIG_IS_ENABLED(ADC)
	unsigned int val;
	struct udevice *dev;
	struct uclass *uc;
	int ret;

	ret = uclass_get(UCLASS_ADC, &uc);
	if (ret)
		return false;

	ret = -ENODEV;
	uclass_foreach_dev(dev, uc) {
		if (!strncmp(dev->name, "saradc", 6)) {
			ret = adc_channel_single_shot(dev->name,
						      RK_DNL_ADC_CHAN, &val);
			break;
		}
	}

	if (ret == -ENODEV) {
		pr_warn("%s: no saradc device found\n", __func__);
		return false;
	} else if (ret) {
		pr_err("%s: adc_channel_single_shot fail!\n", __func__);
		return false;
	}

	if ((val >= KEY_DOWN_MIN_VAL) && (val <= KEY_DOWN_MAX_VAL))
		return true;
	else
		return false;
#else
	return false;
#endif
}

void rockchip_dnl_mode_check(void)
{
	if (rockchip_dnl_key_pressed()) {
		printf("download key pressed, entering download mode...");
		set_back_to_bootrom_dnl_flag();
		do_reset(NULL, 0, 0, NULL);
	}
}

int setup_boot_mode(void)
{
	void *reg = (void *)CONFIG_ROCKCHIP_BOOT_MODE_REG;
	int boot_mode = readl(reg);

	rockchip_dnl_mode_check();

	boot_mode = readl(reg);
	debug("%s: boot mode 0x%08x\n", __func__, boot_mode);

	/* Clear boot mode */
	writel(BOOT_NORMAL, reg);

	switch (boot_mode) {
	case BOOT_FASTBOOT:
		debug("%s: enter fastboot!\n", __func__);
		env_set("preboot", "setenv preboot; fastboot usb 0");
		break;
	case BOOT_UMS:
		debug("%s: enter UMS!\n", __func__);
		env_set("preboot", "setenv preboot; ums mmc 0");
		break;
	}

	return 0;
}
