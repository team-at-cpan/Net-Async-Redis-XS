#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include <math.h>

/* Back-compatibility */
#ifndef G_LIST
#define G_LIST G_ARRAY
#endif

/* Types of data structures that can nest */
enum PendingStackType {
    array, map, set, attribute, push
};
/* Container representation - basic stack of nested lists */
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
    if(!SvPOK(p))
        croak("expected a string");
    if(SvUTF8(p))
        sv_utf8_downgrade(p, true);

    STRLEN len;
    const char *in = SvPVbyte(p, len);
    const char *ptr = in;
    const char *end = in + len;
    struct pending_stack *ps = NULL;
    AV *results = (AV *) sv_2mortal((SV *) newAV());
    int extracted_item = 0;
    SV *extracted = &PL_sv_undef;
    /* Perl strings _should_ guarantee this, so perhaps better as an assert? */
    if(*end != '\0') {
        croak("no trailing null?");
    }

    /* The shortest command is a single-character null, which has the
     * type `_` followed by CRLF terminator, so that's at least 3
     * characters for a valid command.
     */
    if(len >= 3) { // && *(end - 1) == '\x0A' && *(end - 2) == '\x0D') {
        while(*ptr && ptr < end) {
            /* First step is to check the data type and extract it if we can */
            switch(*ptr++) {
                case '~': /* set */
                case '*': { /* array */
                    int n = 0;
                    /* We effectively want grok_atoUV behaviour, but without having a full UV */
                    while(*ptr >= '0' && *ptr <= '9') {
                        n = (n * 10) + (*ptr - '0');
                        ++ptr;
                    }
                    if(ptr + 2 > end) {
                        goto end_parsing;
                    }
                    if(ptr[0] != '\x0D' || ptr[1] != '\x0A') {
                        croak("protocol violation - array length not followed by CRLF");
                    }
                    ptr += 2;

                    AV *x = (AV *) sv_2mortal((SV *)newAV());
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
                case '>': { /* push (pubsub) */
                    int n = 0;
                    while(*ptr >= '0' && *ptr <= '9') {
                        n = (n * 10) + (*ptr - '0');
                        ++ptr;
                    }
                    if(ptr + 2 > end) {
                        goto end_parsing;
                    }
                    if(ptr[0] != '\x0D' || ptr[1] != '\x0A') {
                        croak("protocol violation - push length not followed by CRLF");
                    }
                    ptr += 2;

                    AV *x = (AV *) sv_2mortal((SV *)newAV());
                    if(n > 0) {
                        av_extend(x, n);
                    }
                    struct pending_stack *pn = Newx(pn, 1, struct pending_stack);
                    pn->data = x;
                    pn->prev = ps;
                    pn->expected = n;
                    pn->type = push;
                    ps = pn;
                    break;
                }
                case '%': { /* hash */
                    int n = 0;
                    while(*ptr >= '0' && *ptr <= '9') {
                        n = (n * 10) + (*ptr - '0');
                        ++ptr;
                    }
                    if(ptr + 2 > end) {
                        goto end_parsing;
                    }

                    /* Hash of key/value pairs */
                    n = n * 2;
                    if(ptr[0] != '\x0D' || ptr[1] != '\x0A') {
                        croak("protocol violation - number of hash entries not followed by CRLF");
                    }
                    ptr += 2;
                    AV *x = (AV *) sv_2mortal((SV *)newAV());
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
                    int negative = 0;
                    if(*ptr == '-') {
                        negative = 1;
                        ++ptr;
                    }
                    while(*ptr >= '0' && *ptr <= '9' && ptr < end) {
                        n = (n * 10) + (*ptr - '0');
                        ++ptr;
                    }
                    if(negative) {
                        n = -n;
                    }
                    if(ptr + 2 > end) {
                        goto end_parsing;
                    }
                    if(ptr[0] != '\x0D' || ptr[1] != '\x0A') {
                        croak("protocol violation - integer not followed by CRLF\n");
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
                case ',': { /* decimal floating-point */
                    float n = 0;
                    int negative = 0;
                    if(*ptr == '-') {
                        negative = 1;
                        ++ptr;
                    }
                    if(*ptr == 'i' || *ptr == 'n') {
                        if(!strncmp(ptr, "inf", 3)) {
                            n = NV_INF;
                        } else if(!strncmp(ptr, "nan", 3)) {
                            n = NV_NAN;
                        }
                    } else {
                        int fraction = 0;
                        int digits = 0;
                        while((*ptr == '.' || (*ptr >= '0' && *ptr <= '9')) && ptr < end) {
                            if(*ptr == '.') {
                                fraction = 1;
                            } else {
                                n = (n * 10) + (*ptr - '0');
                                if(fraction) {
                                    ++digits;
                                }
                            }
                            ++ptr;
                        }
                        if(digits > 0) {
                            n = n / pow(10, digits);
                        }
                    }
                    if(negative) {
                        n = -n;
                    }
                    if(ptr + 2 > end) {
                        goto end_parsing;
                    }
                    if(ptr[0] != '\x0D' || ptr[1] != '\x0A') {
                        croak("protocol violation - decimal numebr not followed by CRLF\n");
                    }
                    ptr += 2;
                    SV *v = newSVnv(n);
                    if(ps) {
                        add_value(ps, v);
                    } else {
                        av_push(results, v);
                        extracted_item = 1;
                    }
                    break;
                }
                case '=': /* verbatim string - fall through */
                case '$': { /* bulk string */
                    int n = 0;
                    SV *v;
                    if(ptr[0] == '-' && ptr[1] == '1') {
                        if(ptr + 4 > end) {
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
                        if(ptr + n + 4 > end) {
                            goto end_parsing;
                        }
                        if(ptr[0] != '\x0D' || ptr[1] != '\x0A') {
                            croak("protocol violation - bulk string length not followed by CRLF");
                        }
                        ptr += 2;
                        v = newSVpvn(ptr, n);
                        ptr += n;
                    }
                    if(ptr[0] != '\x0D' || ptr[1] != '\x0A') {
                        croak("protocol violation - bulk string not terminated by CRLF");
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
                case '(': /* big number - treat as a string for now */
                case '+': { /* string */
                    const char *start = ptr;
                    while(*ptr && (ptr[0] != '\x0D' && ptr[1] != '\x0A' && ptr < end)) {
                        ++ptr;
                    }
                    if(ptr + 2 > end) {
                        goto end_parsing;
                    }
                    if(ptr[0] != '\x0D' || ptr[1] != '\x0A') {
                        croak("protocol violation - string not terminated by CRLF");
                    }
                    int n = ptr - start;
                    SV *v = newSVpvn(start, n);
                    ptr += 2;
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
                    if(ptr + 2 > end) {
                        goto end_parsing;
                    }
                    if(ptr[0] != '\x0D' || ptr[1] != '\x0A') {
                        croak("protocol violation - error not terminated by CRLF");
                    }
                    int n = ptr - start;
                    SV *v = newSVpvn(start, n);
                    ptr += 2;
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
                        croak("protocol violation - single-character null not followed by CRLF");
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

            /* Do some housekeeping after parsing: see if we've accumulated enough
             * data to fill the requirements for one or more levels of our nested container
             * handling.
             */
            while(ps && av_count(ps->data) >= ps->expected) {
                AV *data = ps->data;
                struct pending_stack *orig = ps;
                ps = orig->prev;
                SV *value_ref = newRV((SV *) data);
                if(ps) {
                    av_push(
                        ps->data,
                        value_ref
                   );
                } else {
                    switch(orig->type) {
                    case push: { /* pub/sub is treated as an out-of-bound message */
                        SV *rv = SvRV(this);
                        if(hv_exists((HV *) rv, "pubsub", 6)) {
                            SV **cv_ptr = hv_fetchs((HV *) rv, "pubsub", 0);
                            if(cv_ptr) {
                                CV *cv = (CV *) *cv_ptr;
                                dSP;
                                ENTER;
                                SAVETMPS;
                                PUSHMARK(SP);
                                EXTEND(SP, 1);
                                PUSHs(sv_2mortal(value_ref));
                                PUTBACK;
                                call_sv((SV *) cv, G_VOID | G_DISCARD);
                                FREETMPS;
                                LEAVE;
                            } else {
                                warn("no CV for ->{pubsub}");
                            }
                        } else {
                            warn("no ->{pubsub} handler");
                        }
                        break;
                    }
                    case attribute: {
                        /* attributes aren't used much: for now, we emit as an event,
                         * but eventually would aim to apply this to the response,
                         * by returning a blessed object for example
                         */
                        SV *rv = SvRV(this);
                        if(hv_exists((HV *) rv, "attribute", 9)) {
                            SV **cv_ptr = hv_fetchs((HV *) rv, "attribute", 0);
                            if(cv_ptr) {
                                CV *cv = (CV *) *cv_ptr;
                                dSP;
                                ENTER;
                                SAVETMPS;
                                PUSHMARK(SP);
                                EXTEND(SP, 1);
                                PUSHs(sv_2mortal(value_ref));
                                PUTBACK;
                                call_sv((SV *) cv, G_VOID | G_DISCARD);
                                FREETMPS;
                                LEAVE;
                            } else {
                                warn("no CV for ->{attribute}");
                            }
                        } else {
                            warn("no ->{attribute} handler");
                        }
                        break;
                    }
                    default:
                        /* Yes, we fall through as a default for map and array: unless the
                         * hashrefs option is set, we want to map all key/value pairs to plain
                         * arrays anyway.
                         */
                        av_push(
                            results,
                            value_ref
                        );
                        extracted_item = 1;
                        break;
                    }
                }
                Safefree(orig);
            }

            /* Every time we reach the end of a complete item, we update
             * our parsed string progress and add to our list of things to
             * return.
             */
            if(extracted_item) {
                /* Remove anything we processed */
                sv_chop(p, ptr);
                ptr = SvPVbyte(p, len);
                end = ptr + len;
                extracted_item = 0;
                /* ... and our "list" is only ever going to be a single item if we're in scalar context */
                if (GIMME_V == G_SCALAR) {
                    extracted = av_shift(results);
                    break;
                }
            }
        }
    }
end_parsing:
    /* Clean up our temporary parse stack */
    while(ps) {
        struct pending_stack *orig = ps;
        ps = ps->prev;
        Safefree(orig);
    }

    /* Flatten our results back into scalars for return */
    if (GIMME_V == G_LIST) {
        long count = av_count(results);
        if(count) {
            EXTEND(SP, count);
            for(int i = 0; i < count; ++i) {
                mPUSHs(av_shift(results));
            }
        }
    } else if (GIMME_V == G_SCALAR) {
        mXPUSHs(extracted);
    }
