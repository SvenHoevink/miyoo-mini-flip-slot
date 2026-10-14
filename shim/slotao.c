// A small audio sink over SigmaStar's MI_AO, for slot on the Miyoo Mini Flip.
//
// Why this exists: the device's ALSA is a thin shim that will not play. It
// refuses the core's 32768 Hz, and at 48 kHz every write fails with
// snd_pcm_recover returning -512 (ERESTARTSYS) persistently. The vendor's own
// stack goes through MI_AO, which is what Allium's apps reach for too.
//
// Why C rather than Rust bindings: MI_AUDIO_Attr_t and friends are vendor
// structs whose layout we would otherwise be guessing at, and guessing wrong is
// silent memory corruption. Here the real headers are compiled against.
//
// Why a shared library rather than linking it in: slot already dlopens its
// audio backend (libasound), so this drops into the same pattern and keeps the
// cargo build free of a C toolchain and a vendor SDK.
//
// Built by `task shim`, shipped to System/libslotao.so, loaded by the MI_AO
// sink in patches/0005.
#include <stdlib.h>
#include <string.h>
#include <mi_ao.h>

#define AO_DEV 0
#define AO_CHN 0

static int opened = 0;

// Returns 0 on success, or the MI error code.
int slotao_open(unsigned int rate, unsigned int channels, unsigned int samples_per_frame) {
	if (opened) {
		return 0;
	}

	MI_AUDIO_Attr_t attr;
	memset(&attr, 0, sizeof(attr));
	attr.eSamplerate = (MI_AUDIO_SampleRate_e)rate;
	attr.eBitwidth = E_MI_AUDIO_BIT_WIDTH_16;
	attr.eWorkmode = E_MI_AUDIO_MODE_I2S_MASTER;
	attr.eSoundmode = channels == 2 ? E_MI_AUDIO_SOUND_MODE_STEREO
	                                : E_MI_AUDIO_SOUND_MODE_MONO;
	// Hardware buffer depth, in frames of u32PtNumPerFrm. At 512 frames and
	// 48 kHz each one is 10.7 ms, so this is the second half of the audio
	// latency -- the first being the ring's DRC target in emu.rs. Six was 64 ms
	// and, with the ring at 100 ms, added up to lag that was audible as the
	// sound running behind the picture. Four is 43 ms, which the audio thread
	// has ample slack to keep fed: it does nothing but block in SendFrame and
	// runs at a raised priority.
	//
	// SLOTAO_FRAMES overrides it, so the floor can be found on the device
	// rather than guessed at here.
	unsigned int frames = 4;
	const char *env = getenv("SLOTAO_FRAMES");
	if (env != NULL) {
		int want = atoi(env);
		if (want >= 2 && want <= 16) {
			frames = (unsigned int)want;
		}
	}
	attr.u32FrmNum = frames;
	attr.u32PtNumPerFrm = samples_per_frame;
	attr.u32ChnCnt = channels;
	attr.u32CodecChnCnt = 0;

	MI_S32 err = MI_AO_SetPubAttr(AO_DEV, &attr);
	if (err != 0) {
		return err;
	}
	if ((err = MI_AO_Enable(AO_DEV)) != 0) {
		return err;
	}
	if ((err = MI_AO_EnableChn(AO_DEV, AO_CHN)) != 0) {
		MI_AO_Disable(AO_DEV);
		return err;
	}

	opened = 1;
	return 0;
}

// The device can resample in hardware, which is how the core's 32768 Hz reaches
// a 48 kHz codec without slot resampling in software first. Separate from
// slotao_open because it has to be called on an enabled channel.
int slotao_resample_from(unsigned int in_rate) {
	if (!opened) {
		return -1;
	}
	return MI_AO_EnableReSmp(AO_DEV, AO_CHN, (MI_AUDIO_SampleRate_e)in_rate);
}

// `frames` is sample frames, not bytes. Blocks up to timeout_ms.
int slotao_write(const void *data, unsigned int frames, unsigned int channels, int timeout_ms) {
	if (!opened) {
		return -1;
	}
	MI_AUDIO_Frame_t frame;
	memset(&frame, 0, sizeof(frame));
	frame.eBitwidth = E_MI_AUDIO_BIT_WIDTH_16;
	frame.eSoundmode = channels == 2 ? E_MI_AUDIO_SOUND_MODE_STEREO
	                                 : E_MI_AUDIO_SOUND_MODE_MONO;
	frame.u32Len = frames * channels * 2;
	frame.apVirAddr[0] = (void *)data;
	frame.apVirAddr[1] = NULL;
	return MI_AO_SendFrame(AO_DEV, AO_CHN, &frame, timeout_ms);
}

void slotao_close(void) {
	if (!opened) {
		return;
	}
	MI_AO_DisableReSmp(AO_DEV, AO_CHN);
	MI_AO_ClearChnBuf(AO_DEV, AO_CHN);
	MI_AO_DisableChn(AO_DEV, AO_CHN);
	MI_AO_Disable(AO_DEV);
	opened = 0;
}

// -60 dB is silent, 0 dB is full scale, matching the vendor's own range.
void slotao_set_volume(int db) {
	MI_AO_SetVolume(AO_DEV, db);
	MI_AO_SetMute(AO_DEV, db <= -60 ? 1 : 0);
}
