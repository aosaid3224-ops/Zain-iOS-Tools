#ifndef SP_ROOTHIDE_CORE_H
#define SP_ROOTHIDE_CORE_H

#ifdef __cplusplus
extern "C" {
#endif

int sp_macho_uses_roothide(const char *path);

long sp_arg_path_offset(const char *arg);

#ifdef __cplusplus
}
#endif

#endif
