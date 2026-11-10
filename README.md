# 4d-plugin-float

## Platform

| carbon | cocoa | win32 | win64 |
|:------:|:-----:|:---------:|:---------:|
|<img src="https://cloud.githubusercontent.com/assets/1725068/22371562/1b091f0a-e4db-11e6-8458-8653954a7cce.png" width="24" height="24" />|<img src="https://cloud.githubusercontent.com/assets/1725068/22371562/1b091f0a-e4db-11e6-8458-8653954a7cce.png" width="24" height="24" />|<img src="https://cloud.githubusercontent.com/assets/1725068/22371562/1b091f0a-e4db-11e6-8458-8653954a7cce.png" width="24" height="24" />|<img src="https://cloud.githubusercontent.com/assets/1725068/22371562/1b091f0a-e4db-11e6-8458-8653954a7cce.png" width="24" height="24" />|

### Version

<img src="https://cloud.githubusercontent.com/assets/1725068/18940649/21945000-8645-11e6-86ed-4a0f800e5a73.png" width="32" height="32" /> <img src="https://cloud.githubusercontent.com/assets/1725068/18940648/2192ddba-8645-11e6-864d-6d5692d55717.png" width="32" height="32" /> <img src="https://user-images.githubusercontent.com/1725068/41266195-ddf767b2-6e30-11e8-9d6b-2adf6a9f57a5.png" width="32" height="32" />

![preemption xx](https://user-images.githubusercontent.com/1725068/41327179-4e839948-6efd-11e8-982b-a670d511e04f.png)

### Releases

[1.1](https://github.com/miyako/4d-plugin-float/releases/tag/1.1)

---

# Float plugin

Converts between text and IEEE 754 single-precision (32-bit, `float32`) values stored as 4 bytes in a `BLOB`. 4D's own `Real` is a 64-bit double, so this plugin is what you use to read or write the 4-byte floats found in binary file formats, network protocols and device data. Text is parsed with the C library's `strtof()` and formatted with `snprintf()` (`%f`, `%e` or `%g`), so the text side follows C conventions, not 4D's `String`/`Num` rules.

| Command | Returns | Purpose |
|---|---|---|
| [float to BLOB](#float-to-blob) | `BLOB` | Parse a number in text into a 4-byte float, little or big endian |
| [BLOB to float](#blob-to-float) | `Text` | Format a 4-byte float as text in fixed, scientific or shortest notation |

**Platforms:** macOS 11.5 or later (universal: Apple silicon and Intel), Windows 64-bit.

---

## Requirements & platform notes

- **Failure is silent.** Neither command raises a 4D error. [BLOB to float](#blob-to-float) returns empty text for anything it can't convert; [float to BLOB](#float-to-blob) returns 4 zero bytes (the float `0.0`) for empty or non-numeric text. See [Error handling & troubleshooting](#error-handling--troubleshooting).
- **Only 4-byte BLOBs are converted.** [BLOB to float](#blob-to-float) reads exactly one `float32`. To decode a BLOB holding many floats, copy each 4-byte slice into its own BLOB first (see the examples under [BLOB to float](#blob-to-float)).
- **Little endian is the native byte order** on every platform this plugin runs on (x86_64 and arm64). The plugin implements "little endian" as "keep the bytes in memory order", and big endian as a byte swap.
- **Both commands are thread-safe** (`"threadSafe": true` in the manifest), so they can be called from preemptive processes.
- **Decimal separator.** `strtof()` and `snprintf()` use the C library's numeric locale. Whether 4D changes that locale is not established here; in the default C locale the separator is always a period (`.`), whatever the system's regional settings. Test on your configuration if you exchange this text with `String`/`Num`.
- The Windows 64-bit binary in the bundle is the prebuilt `Float.4DX` from the 1.2 release; the release workflow builds and signs only the macOS binary.

## Maintainer release lifecycle

Run **Bump version** manually on the desired branch, choosing patch, minor or
major. It validates strict `X.Y.Z` source metadata, updates every
`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `Float.xcodeproj` and the
literal source `Info.plist` version fields (including `CFBundleVersion` when
present), and commits only those files. Recognized Xcode references to these
keys are validated and preserved. Both Xcode keys are coordinated release
versions, not independent counters: the original bump contract and source
history agree at 1.2.0. Prebuilt bundle, dependency and 4D schema metadata are
not version authorities and are not rewritten.

The bump pushes explicitly to the selected branch without force or follow-tags,
even with `push.followTags=true`; an advanced, rewound or deleted selected
branch is rejected. It creates no tag and starts no Build.

Run **Build** manually using only the Actions branch selector
(`gh workflow run release.yml --ref <branch>`). There are no typed inputs and
no push trigger. Every checkout uses the immutable selected `github.sha`.
Source validation and publication availability precede the existing universal
macOS build, prebuilt-library checks, architecture/resource verification,
Developer ID signing, ZIP/DMG packaging, accepted notarization of both assets
and DMG stapling. Windows64 remains prebuilt and ships unchanged.
Assets remain `Float-X.Y.Z.zip` and `Float-X.Y.Z.dmg`.

Build runs serialize repository-wide across branches. After all gates, it
rechecks the remote tag and authenticated, paginated releases listing; **any**
same-tag release, including a draft, blocks publication. API, authentication,
network, malformed response and later-page failures fail closed. It creates
`vX.Y.Z` using create-only `POST git/refs` at exactly the selected SHA (even
same-SHA creation races fail), verifies the remote target, then uses create-only
`POST releases` with explicit tag, SHA, name, `draft=false`, `prerelease=false`
and an empty body, preserving the original non-generated notes policy.
Uploads use `gh release upload` without clobbering.

**Manual recovery:** Publication never deletes, patches, rolls back, replaces
assets or retries automatically. A tag, release or partial upload created before
a failure remains for inspection, and another Build for that version will fail.
Inspect the failed run, selected SHA, remote tag, release (including drafts) and
assets before a maintainer decides how to recover manually or prepares a new
source version. Do not blindly rerun publication.

Local regression checks (no native build, signing or remote publication):
`python3 -m unittest discover -s .github/tests -v` and `actionlint`.
Tests use PyYAML (`python3 -m pip install -r .github/tests/requirements.txt`
if unavailable) and disposable local bare Git remotes; all GitHub API calls
are mocked.

## Native ownership maintenance

The bounded audit baseline is `60547f232aaba1be7bdb9b770bb93528d584b627`.
Both root and bundled manifests declare only the two scalar commands above.
That does not exclude dormant helpers: Xcode and both Visual Studio projects
compile the SDK, dispatcher and **all 16 wrapper implementations**. The SDK
header includes all wrapper headers. The Windows definition exports
`FourDPackex`; its actual implementation initializes the engine callback and
calls `PluginMain`, which dispatches selectors 1 and 2.

The complete baseline native inventory (43 tracked files) is:

| Surface | Files / classification |
|---|---|
| Entry | `4DPlugin.cpp`, `4DPlugin.h`, `4D Plugin_Prefix.pch` |
| String and picture wrappers | `Classes/C_TEXT.{cpp,h}`, `ARRAY_TEXT.{cpp,h}`, `C_PICTURE.{cpp,h}` under `4D Plugin API/` |
| Other wrappers | `C_BLOB`, `C_POINTER`, `C_DATE`, `C_INTEGER`, `C_LONGINT`, `C_REAL`, `C_TIME`, `ARRAY_BOOLEAN`, `ARRAY_DATE`, `ARRAY_INTEGER`, `ARRAY_LONGINT`, `ARRAY_REAL`, `ARRAY_TIME`, each `.cpp` and `.h` in the same directory |
| Shared types | `4D Plugin API/Classes/C_TYPES.h` |
| Bundled SDK / exports | `4D Plugin API/4DPluginAPI.{c,h,def}`, `EntryPoints.h`, `Flags.h`, `PrivateTypes.h`, `PublicTypes.h` |

`Float.xcodeproj/project.pbxproj`, `Float.vcxproj`, `Float.vc10.vcxproj` and
their filters establish compilation/include reachability. There are no other
tracked baseline native source extensions or separate third-party native
libraries. Numeric/date/time/Boolean wrappers do not own strings. BLOB text
conversion uses independent `C_TEXT` storage. Scalar command inputs are
copied; text returns use the content setter, not descriptor transfer.

The **actual bundled** `4DPluginAPI.c` SHA-256 is
`2721c3d4338cc2a350599ffcee2a8008abaa756acfd45dd710720c64ca8c8ce3`.
It is byte-identical to the file introduced at the root by
`caf7077851a99c3b17da41e0cf57a311f17af5dd` and to
`float/4D Plugin API/4DPluginAPI.c` in the initial 2019 commit
`e00bc9d67dafc418128bdfaad67fc90dc265e92b`. Its v14 comment and the headers'
v13 comments are not independently verified upstream SDK release identifiers.
The SDK is unchanged by this fix.

Contracts verified in that implementation:

- `PA_SetStringInArray` disposes the old element and shallow-transfers the
  supplied descriptor only for Unicode arrays with non-null data, index
  `0 <= i <= fNbElements`, and a non-null descriptor pointer. Rejections
  retain the caller's owner. `PA_GetStringInArray` is borrowed.
  `ARRAY_TEXT` copies borrowed input and allocates each output independently;
  it must not dispose an accepted transferred string.
- Scalar string/picture variable setters shallow-assign and do not clear
  old contents. Use an Undefined destination before assigning an existing
  owned value or a temporarily borrowed picture. Creating a string/picture
  variable first allocates an empty owner which such a setter overwrites.
  `PA_SetUnistring` / `PA_ReturnString` instead use the engine content setter.
- `PA_GetPictureVariable` is explicitly borrowed; `setPicture` retains.
  `fromFileAtPath` clears its path owner once and clears the output argument
  after retaining it. `setBytes` releases its temporary picture after retain.
  Copy/grayscale/thumbnail return an owning picture to the caller, which must
  eventually call `PA_DisposePicture`. Borrowed synchronous picture inputs
  are still detached before argument cleanup.
- Charset conversion returns **bytes**, excluding the terminator, while
  `CUTF16String` lengths count UTF-16 code units. `createCopy` divides by
  `sizeof(PA_Unichar)`.
- Command handle-allocation failure returns a raw-kind-0 sentinel, not an
  owned string to clear. Method handle-allocation failure returns Undefined.
  The picture commands used here have no owning command return. Independent
  synchronous string arguments and owning method/command returns are
  separately released in the contract regression.

Run the non-release macOS regression with:

```sh
bash tests/run_native_ownership.sh
```

It compiles the **full unchanged SDK**, every production wrapper and the actual
dispatcher with ASan/UBSan, using synthetic fixtures and a strict
engine-boundary callback. Unknown engine/UI calls abort; no actual picture
commands, windows, files, release build phases or external services execute.
String allocations, handles and picture references must balance explicitly
(macOS LeakSanitizer is unavailable). Coverage includes exact ASCII, BMP,
surrogate pairs and empty text; allocated/null empty strings; byte capacities
and terminators; independent transfers/borrowed copies; array replacement,
shrink and clear; rejected destinations; retained handoffs; unchanged/replaced
picture inputs; and command/handle failures.

For baseline reproduction, extract the native sources with `git archive`
into a separate directory, then run the **same current harness**:

```sh
git archive 60547f232aaba1be7bdb9b770bb93528d584b627 \
  '4D Plugin API' 4DPlugin.cpp 4DPlugin.h | tar -x -C /path/to/empty-baseline
bash tests/run_native_ownership.sh /path/to/empty-baseline --expect-baseline-defects
```

Eight named baseline failures are expected: `path` (double disposal),
`path-empty` (retained output leak with null empty strings), `bytes` (temporary
reference leak), `copy` (ASan heap-buffer-overflow), `copy-empty` (overwritten
empty string/picture owners), and `gray`, `size`, `thumbnail` (overwritten
empty picture owners). The fixed source passes all 39 matrix invocations.

**Deferred / not certified:** `C_POINTER::getVariable` metadata ownership,
SDK-only app-path outputs and picture-data metadata output ownership cannot
be settled from the bundled forwarding code; no speculative cleanup is added.
Failed picture-data outputs are not adopted or cleared. Object/collection
getters and JSON Parse are not used by first-party code here. Successful
ordinary-array tests do not certify resize OOM: the bundled SDK updates its
element count even if handle resize fails. SDK/OOM hardening, generic wrapper
copyability, unrelated algorithms and full platform testing are outside this
fix. This is native macOS host-shim evidence, not execution in real 4D or
Windows and not reproduction of the originating Poppler Windows crash.

Both existing Actions workflows are manual-only. Native regression compilation
bypasses the Xcode signing/notarization/packaging phase; it neither runs nor
changes release workflows, project files, manifests, SDK files or binaries.
The separate **Native ownership regression** pull-request workflow runs only
the fixed-source and immutable-baseline shim tests, with read-only permissions
and no artifact publication.

---

## float to BLOB

### Syntax

```
bytes:=float to BLOB ( float {; endian} )
```

| Parameter | Type | Description |
|---|---|---|
| `float` | Text | Number to convert, e.g. `"0.01"`, `"-9999.999"`, `"1e-3"` |
| `endian` | Longint | Byte order of the result: `Float little endian` (0, default) or `Float big endian` (1) |
| Result | BLOB | Always 4 bytes: the IEEE 754 single-precision value |

### Description

`float to BLOB` parses `float` with `strtof()` and returns the nearest `float32` value as 4 bytes.

- Leading white space is skipped and parsing stops at the first character that can't be part of a number, so `"1.5kg"` gives `1.5`. A comma is not a decimal separator in the C locale: `"1,5"` gives `1`.
- Besides plain decimals, `strtof()` accepts exponents (`"1e-3"`), hexadecimal floats (`"0x1p-2"` = `0.25`), `"inf"`/`"infinity"` and `"nan"`, case-insensitively.
- Text that doesn't start with a number gives `0.0`. Empty text also gives 4 zero bytes.
- A value too large for a `float32` (e.g. `"1e40"`) becomes infinity (`7F800000` big endian). A value too small becomes zero or a subnormal number.
- The value is rounded to the nearest `float32`: `"0.01"` is stored as `3C23D70A` (big endian), which reads back as `0.0099999998`.
- `endian`: `1` swaps the bytes to big endian. **Any other value, including omitting it, gives little endian.**

### Example

From the plugin's original README:

```4d
$bytes:=float to BLOB ("0.01";Float big endian)

ASSERT(BLOB size($bytes)=4)
ASSERT($bytes{0}=0x003C)
ASSERT($bytes{1}=0x0023)
ASSERT($bytes{2}=0x00D7)
ASSERT($bytes{3}=0x000A)

$bytes:=float to BLOB ("-0.01";Float big endian)

ASSERT(BLOB size($bytes)=4)
ASSERT($bytes{0}=0x00BC)
ASSERT($bytes{1}=0x0023)
ASSERT($bytes{2}=0x00D7)
ASSERT($bytes{3}=0x000A)

$bytes:=float to BLOB ("9999.999";Float big endian)

ASSERT(BLOB size($bytes)=4)
ASSERT($bytes{0}=0x0046)
ASSERT($bytes{1}=0x001C)
ASSERT($bytes{2}=0x003F)
ASSERT($bytes{3}=0x00FF)

$bytes:=float to BLOB ("-9999.999";Float big endian)

ASSERT(BLOB size($bytes)=4)
ASSERT($bytes{0}=0x00C6)
ASSERT($bytes{1}=0x001C)
ASSERT($bytes{2}=0x003F)
ASSERT($bytes{3}=0x00FF)
```

```4d
$bytes:=float to BLOB ("1";Float little endian)

ASSERT(BLOB size($bytes)=4)
ASSERT($bytes{3}=0x003F)
ASSERT($bytes{2}=0x0080)
ASSERT($bytes{1}=0x0000)
ASSERT($bytes{0}=0x0000)
```

Writing several floats into one BLOB, big endian (as many file formats require):

```4d
C_BLOB($all;$one)
C_LONGINT($i;$j)
ARRAY TEXT($values;3)
$values{1}:="1.5"
$values{2}:="-0.25"
$values{3}:="100"

SET BLOB SIZE($all;Size of array($values)*4)
For ($i;1;Size of array($values))
	$one:=float to BLOB ($values{$i};Float big endian)
	For ($j;0;3)
		$all{(($i-1)*4)+$j}:=$one{$j}
	End for
End for
```

---

## BLOB to float

### Syntax

```
float:=BLOB to float ( bytes {; format {; endian {; precision}}} )
```

| Parameter | Type | Description |
|---|---|---|
| `bytes` | BLOB | Exactly 4 bytes holding one IEEE 754 single-precision value |
| `format` | Longint | `Float decimal floating point` (0, default), `Float scientific notation` (1) or `Float shortest format` (2) |
| `endian` | Longint | Byte order of `bytes`: `Float little endian` (0, default) or `Float big endian` (1) |
| `precision` | Longint | Digits passed to the format (see below). `0` or omitted = 8 |
| Result | Text | The value as text, or empty text if it can't be converted |

### Description

`BLOB to float` reads `bytes` as a `float32` and formats it with `snprintf()`:

| `format` | C format | `1` with the default precision |
|---|---|---|
| `Float decimal floating point` (0) | `%.*f` | `1.00000000` |
| `Float scientific notation` (1) | `%.*e` | `1.00000000e+00` |
| `Float shortest format` (2) | `%.*g` | `1` |

`precision` is the number of digits after the decimal point for `%f` and `%e`, and the maximum number of significant digits for `%g` (which drops trailing zeros):

- `0` or omitted: 8 (`FLT_DECIMAL_DIG - 1`). With `%e` that is nine significant digits, enough to restore the exact `float32` value.
- `-1`: no digits after the decimal point (`1.5` gives `"2"` with `%f`; `%g` treats it as 1 significant digit).
- Any other positive value is used as is. Any other negative value makes the C library use its default of 6.

**`Float precision default` is `-1`, not `0`.** Passing that constant gives no decimals; to get the 8-digit default, omit `precision` or pass `0`.

- `bytes` must be exactly 4 bytes long. Any other size returns empty text. (Fixed in this version: BLOBs of 260, 516, … bytes used to be accepted and their first 4 bytes converted, because the size was truncated to 8 bits.)
- A `format` other than 0, 1 or 2 returns empty text.
- `endian`: `1` reads the bytes as big endian. **Any other value, including omitting it, reads them as little endian.**
- Infinity and NaN are formatted by the C library as `inf`, `-inf` and `nan`.
- `%f` writes every integer digit: the largest `float32` (about `3.4e38`) gives 39 digits before the decimal point.
- A `precision` so large that the text can't be produced (e.g. `2147483647`) returns empty text. (Fixed in this version: it could crash 4D before.) Large values that still succeed allocate that many characters, so keep `precision` reasonable.

### Example

From the plugin's original README:

```4d
$bytes:=float to BLOB ("1";Float little endian)

$f:=BLOB to float ($bytes;Float decimal floating point)  //1.00000000
$e:=BLOB to float ($bytes;Float scientific notation)  //1.00000000e+00
$g:=BLOB to float ($bytes;Float shortest format)  //1

$bytes:=float to BLOB ("1";Float big endian)

ASSERT(BLOB size($bytes)=4)
ASSERT($bytes{0}=0x003F)
ASSERT($bytes{1}=0x0080)
ASSERT($bytes{2}=0x0000)
ASSERT($bytes{3}=0x0000)

$f:=BLOB to float ($bytes;Float decimal floating point;Float big endian)
$e:=BLOB to float ($bytes;Float scientific notation;Float big endian)
$g:=BLOB to float ($bytes;Float shortest format;Float big endian)
```

Reading every float from a BLOB of big-endian `float32` values (e.g. one loaded from a file):

```4d
C_BLOB($all;$one)
C_LONGINT($i;$j)
C_TEXT($value)
ARRAY TEXT($values;0)

SET BLOB SIZE($one;4)
For ($i;0;(BLOB size($all)\4)-1)
	For ($j;0;3)
		$one{$j}:=$all{($i*4)+$j}
	End for
	$value:=BLOB to float ($one;Float shortest format;Float big endian)
	APPEND TO ARRAY($values;$value)
End for
```

Choosing the precision:

```4d
$bytes:=float to BLOB ("3.14159265")
$t:=BLOB to float ($bytes)  //"3.14159274" (8 decimals of the float32 nearest to pi)
$t:=BLOB to float ($bytes;Float decimal floating point;Float little endian;2)  //"3.14"
$t:=BLOB to float ($bytes;Float decimal floating point;Float little endian;-1)  //"3"
```

---

## Constants

| Constant | Value | Used by |
|---|---|---|
| `Float decimal floating point` | 0 | `format` of [BLOB to float](#blob-to-float) (`%f`) |
| `Float scientific notation` | 1 | `format` of [BLOB to float](#blob-to-float) (`%e`) |
| `Float shortest format` | 2 | `format` of [BLOB to float](#blob-to-float) (`%g`) |
| `Float little endian` | 0 | `endian` of both commands |
| `Float big endian` | 1 | `endian` of both commands |
| `Float precision default` | -1 | `precision` of [BLOB to float](#blob-to-float): **no** digits after the decimal point, despite its name |

---

## Error handling & troubleshooting

- **Empty text from BLOB to float.** The BLOB isn't exactly 4 bytes, `format` isn't 0, 1 or 2, or `precision` is too large for the text to be produced. No 4D error is raised.
- **float to BLOB returns `0.0` for bad input.** Empty or non-numeric text gives 4 zero bytes, indistinguishable from `"0"`. Validate the text before converting if that matters.
- **Numbers cut short at a comma.** `strtof()` stops at the first character it doesn't recognise, and in the C locale that includes `,`. Replace the separator before calling [float to BLOB](#float-to-blob).
- **No decimals when passing `Float precision default`.** The constant is `-1`, which means "no digits after the decimal point". Omit `precision` or pass `0` for the 8-digit default.
- **Bytes in the wrong order.** Any `endian` value other than `Float big endian` (1) means little endian. Check which order the file or protocol uses: network protocols and many file formats are big endian.
- **`0.01` comes back as `9.99999978e-03`.** A `float32` holds about 7 significant decimal digits and stores the nearest representable value. Use `Float shortest format` with a precision of 7 or less to hide the rounding.
- **Infinity instead of a number.** The text was outside the `float32` range (about ±3.4e38).

---

## Quick reference

```4d
$b:=float to BLOB ("0.01")  // 4 bytes, little endian
$b:=float to BLOB ("0.01";Float big endian)
$t:=BLOB to float ($b;Float decimal floating point;Float big endian)  // "0.01000000"
$t:=BLOB to float ($b;Float scientific notation;Float big endian)  // "9.99999978e-03"
$t:=BLOB to float ($b;Float shortest format;Float big endian;7)  // "0.01"
```
