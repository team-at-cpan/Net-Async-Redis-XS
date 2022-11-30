#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

enum PendingStackType {
    array, map, set, attribute, push
};
struct pending_stack {
    AV *data;
    struct pending_stack *prev;
    long expected;
    enum PendingStackType type;
};

void
add_value(struct pending_stack *target, SV *v)
{
    if(!target)
        return;

    av_push(
        target->data,
        v
    );
}

MODULE = Net::Async::Redis::XS  PACKAGE = Net::Async::Redis::XS

PROTOTYPES: DISABLE

AV *
decode_buffer(SV *this, SV *p)
PPCODE:
    /* Plain bytestring required: no magic, no UTF-8, no nonsense */
    if(SvTYPE(p) != SVt_PV)
        croak("expected a string");
    if(SvUTF8(p))
        sv_utf8_downgrade(p, true);

    STRLEN len;
    const char *in = SvPVbyte(p, len);
    const char *ptr = in;
    const char *end = in + len;
    struct pending_stack *ps = NULL;
    AV *results = newAV();
    int extracted_item = 0;
    SV *extracted = &PL_sv_undef;
    /* Shortcut for "we have incomplete data" */
    if(*end != '\0') {
        croak("no trailing null?");
    }
    if(len > 3 && *(end - 1) == '\x0A' && *(end - 2) == '\x0D') {
        while(*ptr && ptr < end) {
            switch(*ptr++) {
                case '*': { /* array */
                    int n = 0;
                    while(*ptr >= '0' && *ptr <= '9' && ptr < end) {
                        n = (n * 10) + (*ptr - '0');
                        ++ptr;
                    }
                    if(ptr + 2 > end) {
                        warn("Unable to parse array, past the end");
                        goto end_parsing;
                    }
                    if(ptr[0] != '\x0D' || ptr[1] != '\x0A') {
                        croak("protocol violation");
                    }
                    ptr += 2;
                    AV *x = newAV();
                    if(n > 0) {
                        av_extend(x, n);
                    }
                    struct pending_stack *pn = Newx(pn, 1, struct pending_stack);
                    pn->data = x;
                    pn->prev = ps;
                    pn->expected = n;
                    pn->type = array;
                    ps = pn;
                    break;
                }
                case '%': { /* hash */
                    int n = 0;
                    while(*ptr >= '0' && *ptr <= '9' && ptr < end) {
                        n = (n * 10) + (*ptr - '0');
                        ++ptr;
                    }
                    if(ptr + 2 > end) {
                        warn("Unable to parse hash, past the end");
                        goto end_parsing;
                    }
                    /* Hash of key/value pairs */
                    n = n * 2;
                    if(ptr[0] != '\x0D' || ptr[1] != '\x0A') {
                        croak("protocol violation");
                    }
                    ptr += 2;
                    AV *x = newAV();
                    if(n > 0) {
                        av_extend(x, n);
                    }
                    struct pending_stack *pn = Newx(pn, 1, struct pending_stack);
                    pn->data = x;
                    pn->prev = ps;
                    pn->expected = n;
                    pn->type = map;
                    ps = pn;
                    break;
                }
                case ':': { /* integer */
                    int n = 0;
                    while(*ptr >= '0' && *ptr <= '9' && ptr < end) {
                        n = (n * 10) + (*ptr - '0');
                        ++ptr;
                    }
                    if(ptr + 2 > end) {
                        warn("Unable to parse integer, past the end");
                        goto end_parsing;
                    }
                    if(ptr[0] != '\x0D' || ptr[1] != '\x0A') {
                        croak("protocol violation\n");
                    }
                    ptr += 2;
                    SV *v = newSViv(n);
                    if(ps) {
                        add_value(ps, v);
                    } else {
                        av_push(results, v);
                        extracted_item = 1;
                    }
                    break;
                }
                case '$': { /* bulk string */
                    int n = 0;
                    SV *v;
                    if(ptr[0] == '-' && ptr[1] == '1') {
                        if(ptr + 4 > end) {
                            warn("Unable to parse undef string, past the end");
                            goto end_parsing;
                        }
                        // null
                        ptr += 2;
                        v = &PL_sv_undef;
                    } else {
                        while(*ptr >= '0' && *ptr <= '9' && ptr < end) {
                            n = (n * 10) + (*ptr - '0');
                            ++ptr;
                        }
                        if(ptr + n + 2 > end) {
                            warn("Unable to parse bulk string, past the end");
                            goto end_parsing;
                        }
                        if(ptr[0] != '\x0D' || ptr[1] != '\x0A') {
                            croak("protocol violation");
                        }
                        ptr += 2;
                        v = newSVpvn(ptr, n);
                        ptr += n;
                    }
                    if(ptr[0] != '\x0D' || ptr[1] != '\x0A') {
                        croak("protocol violation");
                    }
                    ptr += 2;
                    if(ps) {
                        add_value(ps, v);
                    } else {
                        av_push(results, v);
                        extracted_item = 1;
                    }
                    break;
                }
                case '+': { /* string */
                    const char *start = ptr;
                    while(*ptr && (ptr[0] != '\x0D' && ptr[1] != '\x0A' && ptr < end)) {
                        ++ptr;
                    }
                    if(ptr + 2 > end) {
                        warn("Unable to parse regular string, past the end");
                        goto end_parsing;
                    }
                    int n = ptr - start;
                    char *str = Newx(str, n + 1, char);
                    strncpy(str, start, n);
                    str[n] = '\0';
                    ptr += 2;
                    SV *v = newSVpvn(str, n);
                    if(ps) {
                        add_value(ps, v);
                    } else {
                        av_push(results, v);
                        extracted_item = 1;
                    }
                    break;
                }
                case '-': { /* error */
                    const char *start = ptr;
                    while(*ptr && (ptr[0] != '\x0D' && ptr[1] != '\x0A' && ptr < end)) {
                        ++ptr;
                    }
                    if(ptr > end) {
                        warn("Unable to parse error, past the end");
                        goto end_parsing;
                    }
                    int n = ptr - start;
                    char *str = Newx(str, n + 1, char);
                    strncpy(str, start, n);
                    str[n] = '\0';
                    ptr += 2;
                    SV *v = newSVpvn(str, n);
                    SV *rv = SvRV(this);

                    /* Remove anything we processed - we're doing this _before_ the call,
                     * since it may throw an exception */
                    sv_chop(p, ptr);
                    ptr = SvPVbyte(p, len);
                    end = ptr + len - 1;
                    if(hv_exists((HV *) rv, "error", 5)) {
                        SV **cv_ptr = hv_fetchs((HV *) rv, "error", 0);
                        if(cv_ptr) {
                            CV *cv = (CV *) *cv_ptr;
                            dSP;
                            ENTER;
                            SAVETMPS;
                            PUSHMARK(SP);
                            EXTEND(SP, 1);
                            PUSHs(sv_2mortal(v));
                            PUTBACK;
                            call_sv((SV *) cv, G_VOID | G_DISCARD);
                            FREETMPS;
                            LEAVE;
                        } else {
                            warn("no CV for ->{error}");
                        }
                    } else {
                        warn("no ->{error} handler");
                    }
                    /* Note that we are _not_ setting extracted_item here, because there
                     * were no items to put in results, and we've already updated the buffer
                     * to move past the error item. */
                    break;
                }
                case '_': { /* single-character null */
                    int n = 0;
                    SV *v = &PL_sv_undef;
                    if(ptr + 2 > end) {
                        goto end_parsing;
                    }
                    if(ptr[0] != '\x0D' || ptr[1] != '\x0A') {
                        croak("protocol violation");
                    }
                    ptr += 2;
                    if(ps) {
                        add_value(ps, v);
                    } else {
                        av_push(results, v);
                        extracted_item = 1;
                    }
                    break;
                }
                default:
                    croak("Unknown type %d, bail out", ptr[-1]);
            }
            while(ps && av_count(ps->data) >= ps->expected) {
                AV *data = ps->data;
                struct pending_stack *orig = ps;
                ps = orig->prev;
                Safefree(orig);
                if(ps) {
                    av_push(
                        ps->data,
                        newRV((SV *) data)
                   );
                } else {
                    av_push(
                        results,
                        newRV((SV *) data)
                    );
                    extracted_item = 1;
                }
            }
            if(extracted_item) {
                /* Remove anything we processed */
                sv_chop(p, ptr);
                ptr = SvPVbyte(p, len);
                end = ptr + len;
                extracted_item = 0;
                if (GIMME_V == G_SCALAR) {
                    extracted = *av_fetch(results, 0, 1);
                    break;
                }
            }
        }
    }
end_parsing:
    /* Flatten our results back into scalars for return */
    long count = av_count(results);
    if (GIMME_V == G_ARRAY) {
        if(count) {
            EXTEND(SP, count);
            for(int i = 0; i < count; ++i) {
                mPUSHs(*av_fetch(results, i, 1));
            }
        }
    } else if (GIMME_V == G_SCALAR) {
        if(count > 0) {
            mXPUSHs(*av_fetch(results, 0, 1));
        } else {
            mXPUSHs(&PL_sv_undef);
        }
    }
    // av_clear(results);
