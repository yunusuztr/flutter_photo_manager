// Temporary measurement probe for the fork's ci/title-budget branch.
// It is NOT part of the upstream change. It records how Apple Foundation
// segments composed character sequences and how long a file name may be on
// the runner's file system, so the title budget is designed from measured
// behaviour instead of a model.
#import <Foundation/Foundation.h>
#include <dirent.h>
#include <string.h>

static NSString *CP(UTF32Char c) {
    UTF32Char le = NSSwapHostIntToLittle(c);
    return [[NSString alloc] initWithBytes:&le length:4 encoding:NSUTF32LittleEndianStringEncoding];
}

static NSString *Rep(NSString *s, NSUInteger n) {
    NSMutableString *m = [NSMutableString string];
    for (NSUInteger i = 0; i < n; i++) {
        [m appendString:s];
    }
    return m;
}

static NSString *HexOf(const unsigned char *bytes, size_t n, size_t max) {
    NSMutableString *h = [NSMutableString string];
    for (size_t i = 0; i < n && i < max; i++) {
        [h appendFormat:@"%02x", bytes[i]];
    }
    if (n > max) {
        [h appendString:@".."];
    }
    return h;
}

static size_t FSLen(NSString *s, BOOL *ok, char *buf, size_t cap) {
    *ok = [s getFileSystemRepresentation:buf maxLength:cap];
    return *ok ? strlen(buf) : 0;
}

static void Seq(const char *label, NSString *s) {
    NSUInteger probe = MIN((NSUInteger)40, s.length);
    NSRange expanded = [s rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, probe)];
    NSString *at40 = @"n/a";
    if (s.length > 40) {
        at40 = NSStringFromRange([s rangeOfComposedCharacterSequenceAtIndex:40]);
    }
    __block NSUInteger count = 0;
    __block NSUInteger longest = 0;
    NSMutableArray<NSNumber *> *first = [NSMutableArray array];
    [s enumerateSubstringsInRange:NSMakeRange(0, s.length)
                          options:NSStringEnumerationByComposedCharacterSequences
                       usingBlock:^(NSString *sub, NSRange r, NSRange er, BOOL *stop) {
        count++;
        longest = MAX(longest, r.length);
        if (first.count < 8) {
            [first addObject:@(r.length)];
        }
    }];
    printf("[seq] %-34s len=%-5lu forRange{0,%lu}=%-12s atIndex40=%-10s sequences=%-4lu longest=%-5lu first=%s\n",
           label, (unsigned long)s.length, (unsigned long)probe,
           NSStringFromRange(expanded).UTF8String, at40.UTF8String,
           (unsigned long)count, (unsigned long)longest,
           [[first componentsJoinedByString:@","] UTF8String]);
}

static void FS(const char *label, NSString *s) {
    static char buf[16384];
    BOOL ok = NO;
    size_t fs = FSLen(s, &ok, buf, sizeof buf);
    NSUInteger u8 = [s lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    NSUInteger nfd = [[s decomposedStringWithCanonicalMapping] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    NSUInteger nfc = [[s precomposedStringWithCanonicalMapping] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    printf("[fsrep] %-26s utf16=%-5lu utf8=%-5lu nfcUtf8=%-5lu nfdUtf8=%-5lu fsRep=%s%-5lu head=%s\n",
           label, (unsigned long)s.length, (unsigned long)u8, (unsigned long)nfc, (unsigned long)nfd,
           ok ? "" : "FAIL ", (unsigned long)fs,
           ok ? HexOf((const unsigned char *)buf, fs, 18).UTF8String : "");
}

static void Copy(NSString *dir, NSURL *source, const char *label, NSString *name) {
    static char buf[16384];
    BOOL fsOK = NO;
    size_t fs = FSLen(name, &fsOK, buf, sizeof buf);
    NSString *path = [dir stringByAppendingPathComponent:name];
    NSError *error = nil;
    BOOL ok = [[NSFileManager defaultManager] copyItemAtURL:source
                                                      toURL:[NSURL fileURLWithPath:path]
                                                      error:&error];
    printf("[copy] %-34s utf16=%-4lu utf8=%-4lu fsRep=%s%-4lu -> %s",
           label, (unsigned long)name.length,
           (unsigned long)[name lengthOfBytesUsingEncoding:NSUTF8StringEncoding],
           fsOK ? "" : "FAIL ", (unsigned long)fs, ok ? "OK" : "FAILED");
    if (!ok) {
        NSError *under = error.userInfo[NSUnderlyingErrorKey];
        printf(" %s %ld", error.domain.UTF8String, (long)error.code);
        if (under) {
            printf(" (underlying %s %ld)", under.domain.UTF8String, (long)under.code);
        }
    }
    printf("\n");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSProcessInfo *info = [NSProcessInfo processInfo];
        printf("[env] os=%s foundation=%.1f\n",
               info.operatingSystemVersionString.UTF8String, NSFoundationVersionNumber);

        NSString *acute = CP(0x0301);
        NSString *hangulSyllable = CP(0xD55C);          // precomposed, decomposes to 3 jamo
        NSString *eAcute = CP(0x00E9);                  // precomposed e + acute
        NSString *vietnamese = CP(0x1EC7);              // e + dot below + circumflex
        NSString *greek = CP(0x1F82);                   // alpha + 3 marks
        NSString *ohm = CP(0x2126);                     // in the HFS+ exclusion range
        NSString *flagTR = [CP(0x1F1F9) stringByAppendingString:CP(0x1F1F7)];
        NSString *grin = CP(0x1F600);
        NSString *thumbs = [CP(0x1F44D) stringByAppendingString:CP(0x1F3FD)];
        NSString *zwj = CP(0x200D);
        NSString *family = [@[CP(0x1F468), CP(0x1F469), CP(0x1F467), CP(0x1F466)] componentsJoinedByString:zwj];
        NSString *keycap = [@"1" stringByAppendingString:[CP(0xFE0F) stringByAppendingString:CP(0x20E3)]];
        NSString *jamo = [@[CP(0x1112), CP(0x1161), CP(0x11AB)] componentsJoinedByString:@""];
        unichar lone[] = {0xD83D};
        NSString *loneHigh = [NSString stringWithCharacters:lone length:1];
        NSString *a39 = Rep(@"a", 39);

        printf("\n== composed character sequences ==\n");
        Seq("a + 200 U+0301 (maintainer case)", [@"a" stringByAppendingString:Rep(acute, 200)]);
        Seq("a + 5000 U+0301", [@"a" stringByAppendingString:Rep(acute, 5000)]);
        Seq("39 a + e + 200 U+0301", [[a39 stringByAppendingString:@"e"] stringByAppendingString:Rep(acute, 200)]);
        Seq("38 a + TR flag + tail", [[Rep(@"a", 38) stringByAppendingString:flagTR] stringByAppendingString:@"bbbb"]);
        Seq("39 a + grin + tail", [[a39 stringByAppendingString:grin] stringByAppendingString:@"bbbb"]);
        Seq("35 a + family ZWJ + tail", [[Rep(@"a", 35) stringByAppendingString:family] stringByAppendingString:@"bbbb"]);
        Seq("39 a + thumbs+tone + tail", [[a39 stringByAppendingString:thumbs] stringByAppendingString:@"bbbb"]);
        Seq("39 a + keycap + tail", [[a39 stringByAppendingString:keycap] stringByAppendingString:@"bbbb"]);
        Seq("39 a + e U+0301 + tail", [[a39 stringByAppendingString:[@"e" stringByAppendingString:acute]] stringByAppendingString:@"bbbb"]);
        Seq("39 a + CRLF + tail", [a39 stringByAppendingString:@"\r\nbbbb"]);
        Seq("38 a + jamo LVT + tail", [[Rep(@"a", 38) stringByAppendingString:jamo] stringByAppendingString:@"bbbb"]);
        Seq("40 a + lone high + tail", [[Rep(@"a", 40) stringByAppendingString:loneHigh] stringByAppendingString:@"bbbb"]);
        Seq("39 a + lone high + tail", [[a39 stringByAppendingString:loneHigh] stringByAppendingString:@"bbbb"]);
        Seq("long latin (60)", Rep(@"Holiday ", 8));

        printf("\n== file system representation ==\n");
        FS("e acute precomposed", eAcute);
        FS("hangul syllable", hangulSyllable);
        FS("40 hangul syllables", Rep(hangulSyllable, 40));
        FS("vietnamese e", vietnamese);
        FS("40 vietnamese e", Rep(vietnamese, 40));
        FS("greek alpha + 3 marks", greek);
        FS("ohm sign (excluded range)", ohm);
        FS("a + 200 U+0301", [@"a" stringByAppendingString:Rep(acute, 200)]);
        FS("grin emoji", grin);
        FS("lone high surrogate", [@"a" stringByAppendingString:loneHigh]);
        @try {
            const char *raw = [[@"a" stringByAppendingString:loneHigh] fileSystemRepresentation];
            printf("[fsrep] fileSystemRepresentation on lone surrogate returned %s\n", raw ? "non-NULL" : "NULL");
        } @catch (NSException *e) {
            printf("[fsrep] fileSystemRepresentation on lone surrogate RAISED %s\n", e.name.UTF8String);
        }

        printf("\n== copyItemAtURL:toURL: into a fresh directory ==\n");
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"pm-probe-%@", [NSUUID UUID].UUIDString]];
        NSError *mkdirError = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&mkdirError]) {
            printf("[copy] cannot create %s: %s\n", dir.UTF8String, mkdirError.description.UTF8String);
            return 1;
        }
        printf("[copy] directory %s\n", dir.UTF8String);
        NSString *sourcePath = [dir stringByAppendingPathComponent:@"source.bin"];
        [[@"probe" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:sourcePath atomically:NO];
        NSURL *source = [NSURL fileURLWithPath:sourcePath];

        NSString *prefix = @"ED7AC36B-A150-4C38-BB8C-B6D696F4F2ED_L0_001_1756200000.123456_o_";
        printf("[copy] realistic prefix length %lu\n", (unsigned long)prefix.length);
        Copy(dir, source, "ascii 255", Rep(@"a", 255));
        Copy(dir, source, "ascii 256", Rep(@"b", 256));
        Copy(dir, source, "28 hangul (84 B nfc, 252 B nfd)", Rep(hangulSyllable, 28));
        Copy(dir, source, "29 hangul (87 B nfc, 261 B nfd)", Rep(hangulSyllable, 29));
        Copy(dir, source, "85 hangul (255 B nfc)", Rep(hangulSyllable, 85));
        Copy(dir, source, "127 e-acute (254 B nfc)", Rep(eAcute, 127));
        Copy(dir, source, "prefix + a+200 marks + .mov", [[prefix stringByAppendingString:[@"a" stringByAppendingString:Rep(acute, 200)]] stringByAppendingString:@".mov"]);
        Copy(dir, source, "prefix + 40 hangul + .mov.pmcache", [[prefix stringByAppendingString:Rep(hangulSyllable, 40)] stringByAppendingString:@".mov.pmcache"]);
        Copy(dir, source, "prefix + 40 vietnamese + .mov.pmcache", [[prefix stringByAppendingString:Rep(vietnamese, 40)] stringByAppendingString:@".mov.pmcache"]);
        Copy(dir, source, "prefix + 40 greek + .mov.pmcache", [[prefix stringByAppendingString:Rep(greek, 40)] stringByAppendingString:@".mov.pmcache"]);
        Copy(dir, source, "prefix + 20 grin + .mov.pmcache", [[prefix stringByAppendingString:Rep(grin, 20)] stringByAppendingString:@".mov.pmcache"]);
        Copy(dir, source, "prefix + 40 e-acute + .mov.pmcache", [[prefix stringByAppendingString:Rep(eAcute, 40)] stringByAppendingString:@".mov.pmcache"]);

        printf("\n== stored names (readdir) ==\n");
        DIR *d = opendir(dir.fileSystemRepresentation);
        struct dirent *entry;
        while (d && (entry = readdir(d)) != NULL) {
            if (entry->d_name[0] == '.') {
                continue;
            }
            size_t n = strlen(entry->d_name);
            printf("[dir] bytes=%-4zu head=%s\n", n, HexOf((const unsigned char *)entry->d_name, n, 18).UTF8String);
        }
        if (d) {
            closedir(d);
        }
    }
    return 0;
}
