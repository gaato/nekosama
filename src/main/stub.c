#include <moonbit.h>
#include <stdio.h>

// stdout is block-buffered when it is not a terminal (a container's log
// pipe, journald), which holds every log line back until exit.
MOONBIT_FFI_EXPORT
void nekosama_line_buffer_stdout(void) {
  setvbuf(stdout, NULL, _IOLBF, 0);
}
