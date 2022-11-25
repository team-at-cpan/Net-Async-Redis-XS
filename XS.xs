#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

MODULE = Net::Async::Redis::XS  PACKAGE = Net::Async::Redis::XS

PROTOTYPES: DISABLE

SV *
decode(SV *p)
CODE:
    if(SvTYPE(p) != SVt_PV)
        croak("expected a string");
    const char *in = SvPVbyte_nolen(p);
    /* const char *in = "*1\x0D\x0A*1\x0D\x0A*2\x0D\x0A:8\x0D\x0A*6\x0D\x0A+a\x0D\x0A+1\x0D\x0A+b\x0D\x0A+2\x0D\x0A+c\x0D\x0A+3\x0D\x0A"; */
    const char *ptr = in;
    while(*ptr) {
        switch(ptr[0]) {
            case '*': { /* array */
                ++ptr;
                int n = 0;
                while(*ptr >= '0' && *ptr <= '9') {
                    n = (n * 10) + (*ptr - '0');
                    ++ptr;
                }
                if(ptr[0] != '\x0D' || ptr[1] != '\x0A') {
                    croak("protocol violation");
                }
                ptr += 2;
                printf("Have array with %d elements\n", n);
                break;
            }
            case ':': { /* integer */
                ++ptr;
                int n = 0;
                while(*ptr >= '0' && *ptr <= '9') {
                    n = (n * 10) + (*ptr - '0');
                    ++ptr;
                }
                if(ptr[0] != '\x0D' || ptr[1] != '\x0A') {
                    croak("protocol violation\n");
                }
                ptr += 2;
                printf("Have integer %d\n", n);
                RETVAL = newSViv(n);
                return;
            }
            case '+': { /* string */
                ++ptr;
                const char *start = ptr;
                while(*ptr && (ptr[0] != '\x0D' && ptr[1] != '\x0A')) {
                    ++ptr;
                }
                int n = ptr - start;
                char *str = malloc(n + 1);
                strncpy(str, start, n);
                str[n] = '\0';
                ptr += 2;
                printf("Have string %s\n", str);
                break;
            }
            default:
                printf("Unknown type %c, bail out\n", ptr[0]);
                abort();
        }
    }
    RETVAL = newSV(0);
OUTPUT:
    RETVAL
