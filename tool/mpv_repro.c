// Diagnostic harness around the project's patched libmpv.dll.
//
//   (compile from repo root, ucrt64 gcc on PATH)
//   gcc tool/mpv_repro.c -o build/windows/x64/runner/Debug/mpv_repro.exe
//   mpv_repro.exe <urlfile>            # play to EOF (or 180s cap)
//   PROBE=1   mpv_repro.exe <urlfile>  # print source props at FILE_LOADED, exit
//   WAVEFORM=1 mpv_repro.exe <urlfile> # also enable the bulk waveform analyzer
//
// A SetUnhandledExceptionFilter prints the faulting module + address if
// libmpv crashes natively. Exit 0 = clean; huge/negative = native crash.
#include <stdio.h>
#include <stdlib.h>
#include <windows.h>

typedef struct mpv_handle mpv_handle;
typedef struct mpv_event {
    int event_id;
    int error;
    unsigned long long reply_userdata;
    void *data;
} mpv_event;

typedef mpv_handle *(*f_create)(void);
typedef int   (*f_init)(mpv_handle *);
typedef int   (*f_setopt)(mpv_handle *, const char *, const char *);
typedef int   (*f_setprop)(mpv_handle *, const char *, const char *);
typedef char *(*f_getprop)(mpv_handle *, const char *);
typedef int   (*f_cmd)(mpv_handle *, const char **);
typedef mpv_event *(*f_wait)(mpv_handle *, double);
typedef void  (*f_free)(void *);
typedef void  (*f_term)(mpv_handle *);

static LONG WINAPI crash_filter(EXCEPTION_POINTERS *ep) {
    void *addr = ep->ExceptionRecord->ExceptionAddress;
    char modpath[MAX_PATH] = "?";
    HMODULE mod = NULL;
    if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                           GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                           (LPCSTR)addr, &mod)) {
        GetModuleFileNameA(mod, modpath, MAX_PATH);
    }
    fprintf(stdout,
        "\n*** NATIVE CRASH ***\n  code=0x%08lX\n  address=%p\n  module=%s\n  module_base=%p  rva=0x%llX\n",
        ep->ExceptionRecord->ExceptionCode, addr, modpath, (void *)mod,
        (unsigned long long)((char *)addr - (char *)mod));
    fflush(stdout);
    return EXCEPTION_EXECUTE_HANDLER; // terminate
}

static void dump_props(f_getprop getp, f_free freep, mpv_handle *m) {
    const char *names[] = {
        "seekable", "partially-seekable", "demuxer-via-network",
        "current-demuxer", "file-format", "duration", "stream-open-filename",
    };
    printf("HARNESS: --- source properties at FILE_LOADED ---\n");
    for (int i = 0; i < (int)(sizeof(names) / sizeof(names[0])); i++) {
        char *v = getp ? getp(m, names[i]) : NULL;
        printf("HARNESS:   %-22s = %s\n", names[i], v ? v : "(null)");
        if (v && freep) freep(v);
    }
    fflush(stdout);
}

int main(int argc, char **argv) {
    SetUnhandledExceptionFilter(crash_filter);
    if (argc < 2) { fprintf(stderr, "usage: mpv_repro <urlfile>\n"); return 2; }
    FILE *fp = fopen(argv[1], "rb");
    if (!fp) { perror("open url file"); return 2; }
    fseek(fp, 0, SEEK_END); long n = ftell(fp); fseek(fp, 0, SEEK_SET);
    char *url = malloc(n + 1); fread(url, 1, n, fp); url[n] = 0; fclose(fp);
    while (n > 0 && (url[n-1] == '\n' || url[n-1] == '\r' || url[n-1] == ' ')) url[--n] = 0;

    HMODULE h = LoadLibraryA("libmpv.dll");
    if (!h) { fprintf(stderr, "LoadLibrary libmpv.dll failed: %lu\n", GetLastError()); return 2; }
    f_create   mpv_create             = (f_create)  GetProcAddress(h, "mpv_create");
    f_init     mpv_initialize         = (f_init)    GetProcAddress(h, "mpv_initialize");
    f_setopt   mpv_set_option_string  = (f_setopt)  GetProcAddress(h, "mpv_set_option_string");
    f_setprop  mpv_set_property_string= (f_setprop) GetProcAddress(h, "mpv_set_property_string");
    f_getprop  mpv_get_property_string= (f_getprop) GetProcAddress(h, "mpv_get_property_string");
    f_cmd      mpv_command            = (f_cmd)     GetProcAddress(h, "mpv_command");
    f_wait     mpv_wait_event         = (f_wait)    GetProcAddress(h, "mpv_wait_event");
    f_free     mpv_free               = (f_free)    GetProcAddress(h, "mpv_free");
    f_term     mpv_terminate_destroy  = (f_term)    GetProcAddress(h, "mpv_terminate_destroy");
    if (!mpv_create || !mpv_initialize || !mpv_command || !mpv_wait_event) {
        fprintf(stderr, "missing mpv symbols\n"); return 2;
    }

    int probe = getenv("PROBE") != NULL;
    int waveform = getenv("WAVEFORM") != NULL;

    mpv_handle *m = mpv_create();
    mpv_set_option_string(m, "ao", "null");
    mpv_set_option_string(m, "vo", "null");
    mpv_set_option_string(m, "audio-display", "no");
    if (!probe) mpv_set_option_string(m, "untimed", "yes");
    mpv_set_option_string(m, "keep-open", "no");
    mpv_set_option_string(m, "msg-level", probe ? "all=status" : "all=v");
    mpv_set_option_string(m, "terminal", "yes");
    if (mpv_initialize(m) < 0) { fprintf(stderr, "mpv_initialize failed\n"); return 2; }

    if (waveform && mpv_set_property_string) {
        printf("HARNESS: enabling bulk waveform analyzer\n"); fflush(stdout);
        mpv_set_property_string(m, "waveform-enabled", "yes");
    }

    const char *cmd[] = { "loadfile", url, NULL };
    mpv_command(m, cmd);
    printf("HARNESS: loadfile issued\n"); fflush(stdout);

    DWORD start = GetTickCount();
    for (;;) {
        mpv_event *e = mpv_wait_event(m, 1.0);
        int id = e ? e->event_id : -1;
        if (id != 0 && !probe) { printf("HARNESS: event id=%d\n", id); fflush(stdout); }
        if (id == 8) { // FILE_LOADED
            dump_props(mpv_get_property_string, mpv_free, m);
            if (probe) break;
        }
        if (id == 7) { printf("HARNESS: END_FILE -> finished, NO crash\n"); break; }
        if (id == 1) { printf("HARNESS: SHUTDOWN\n"); break; }
        DWORD cap = probe ? 20000 : 180000;
        if (GetTickCount() - start > cap) { printf("HARNESS: %lus cap, NO crash\n", cap/1000); break; }
    }
    mpv_terminate_destroy(m);
    printf("HARNESS: clean exit\n");
    return 0;
}
