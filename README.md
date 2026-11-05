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
