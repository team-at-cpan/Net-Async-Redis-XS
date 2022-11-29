#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

struct pending_stack {
    int expected;
    AV *data;
    struct pending_stack *prev;
};

struct pending_stack *
add_value(struct pending_stack *target, SV *v)
{
    // warn("Add value, target was %p\n", target);
    if(!target)
        return target;

    // warn("Will push data onto %p where top index was %d", target->data, av_top_index(target->data));
    av_push(
        // *av_fetch(target->data, av_top_index(target->data), 1),
        target->data,
        v
    );
    // warn("Count now %d from expected %d\n", av_count(target->data), target->expected);
    while(target && av_count(target->data) >= target->expected) {
        // warn("Emit %d elements in array\n", av_count(target->data));
        AV *data = target->data;
        struct pending_stack *orig = target;
        target = orig->prev;
        Safefree(orig);
        if(target) {
            // warn("Will push to %p the data from %p", target, data);
            av_push(
                target->data,
                newRV((SV *) data)
            );
            // warn("Have pushed our new RV");
        }
    }

    return target;
}

MODULE = Net::Async::Redis::XS  PACKAGE = Net::Async::Redis::XS

PROTOTYPES: DISABLE

SV *
decode_buffer(SV *p)
CODE:
    /* Plain bytestring required: no magic, no UTF-8, no nonsense */
    if(SvTYPE(p) != SVt_PV)
        croak("expected a string");
    if(SvUTF8(p))
        sv_utf8_downgrade(p, true);

    STRLEN len;
    const char *in = SvPVbyte(p, len);
    const char *ptr = in;
    const char *end = in + len - 1;
    struct pending_stack *ps = NULL;
    while(*ptr && ptr < end) {
        switch(*ptr++) {
            case '*': { /* array */
                int n = 0;
                while(*ptr >= '0' && *ptr <= '9' && ptr < end) {
                    n = (n * 10) + (*ptr - '0');
                    ++ptr;
                }
                if(ptr[0] != '\x0D' || ptr[1] != '\x0A') {
                    croak("protocol violation");
                }
                ptr += 2;
                // warn("Have array with %d elements\n", n);
                AV *x = newAV();
                av_extend(x, n);
                // warn("Create new pending stack, previous %p\n", ps);
                struct pending_stack *pn = Newx(pn, 1, struct pending_stack);
                pn->expected = n;
                pn->data = x;
                pn->prev = ps;
                if(ps == NULL) {
                    RETVAL = newRV_inc((SV *) x);
                }
                ps = pn;
                break;
            }
            case ':': { /* integer */
                int n = 0;
                while(*ptr >= '0' && *ptr <= '9' && ptr < end) {
                    n = (n * 10) + (*ptr - '0');
                    ++ptr;
                }
                if(ptr[0] != '\x0D' || ptr[1] != '\x0A') {
                    croak("protocol violation\n");
                }
                ptr += 2;
                // warn("Have integer %d\n", n);
                SV *v = newSViv(n);
                if(ps) {
                    ps = add_value(ps, v);
                } else {
                    RETVAL = v;
                }
                break;
            }
            case '$': { /* bulk string */
                int n = 0;
                SV *v;
                if(ptr[0] == '-' && ptr[1] == '1') {
                    // null
                    ptr += 2;
                    v = &PL_sv_undef;
                } else {
                    while(*ptr >= '0' && *ptr <= '9' && ptr < end) {
                        n = (n * 10) + (*ptr - '0');
                        ++ptr;
                    }
                    if(ptr + n >= end) {
                        croak("incomplete packet");
                    }
                    if(ptr[0] != '\x0D' || ptr[1] != '\x0A') {
                        croak("protocol violation");
                    }
                    ptr += 2;
                    // warn("Have bulk string with %d characters\n", n);
                    v = newSVpvn(ptr, n);
                    ptr += n;
                }
                if(ptr[0] != '\x0D' || ptr[1] != '\x0A') {
                    croak("protocol violation");
                }
                ptr += 2;
                if(ps) {
                    ps = add_value(ps, v);
                } else {
                    RETVAL = v;
                }
                break;
            }
            case '+': { /* string */
                const char *start = ptr;
                while(*ptr && (ptr[0] != '\x0D' && ptr[1] != '\x0A' && ptr < end)) {
                    ++ptr;
                }
                int n = ptr - start;
                char *str = Newx(str, n + 1, char);
                strncpy(str, start, n);
                str[n] = '\0';
                ptr += 2;
                // warn("Have string %s\n", str);
                SV *v = newSVpvn(str, n);
                if(ps) {
                    ps = add_value(ps, v);
                } else {
                    RETVAL = v;
                }
                break;
            }
            case '_': { /* single-character null */
                int n = 0;
                SV *v = &PL_sv_undef;
                if(ptr[0] != '\x0D' || ptr[1] != '\x0A') {
                    croak("protocol violation");
                }
                ptr += 2;
                if(ps) {
                    ps = add_value(ps, v);
                } else {
                    RETVAL = v;
                }
                break;
            }
            default:
                croak("Unknown type %d, bail out", ptr[-1]);
        }
    }
    /* Remove anything we processed */
    if((ptr - in) > 0) {
        sv_chop(p, ptr);
    }
    /* RETVAL = newSV(0); */
OUTPUT:
    RETVAL
