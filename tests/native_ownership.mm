#include "4DPluginAPI.h"
#include "PrivateTypes.h"
#include "EntryPoints.h"
#include <cassert>
#include <codecvt>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <locale>
#include <string>

namespace {
std::map<PA_Unichar*, size_t> strings;
std::map<PA_Handle, size_t> handles;
std::map<PA_Picture, unsigned> pictures;
bool nullEmpty = false;
bool failHandle = false;
bool failCommand = false;
bool replacePicture = true;
CUTF16String expectedPath;
CUTF16String expectedType;

void require(bool condition, const char* message)
{
    if (!condition) {
        std::fprintf(stderr, "ownership assertion: %s\n", message);
        std::abort();
    }
}

CUTF16String text(const PA_Unistring& value)
{
    if (!value.fString) {
        require(value.fLength == 0, "null string has nonzero length");
        return CUTF16String();
    }
    PA_Unichar* pointer = value.fString;
    auto it = strings.find(pointer);
    require(it != strings.end(), "read of released string");
    require(it->second == static_cast<size_t>(value.fLength), "exact string length");
    require(value.fString[value.fLength] == 0, "string terminator");
    return CUTF16String(value.fString, value.fLength);
}

PA_Unistring makeString(const PA_Unichar* source)
{
    size_t length = 0;
    if (source)
        while (source[length]) ++length;
    PA_Unistring result = {};
    if (length || !nullEmpty) {
        result.fString = static_cast<PA_Unichar*>(std::malloc((length + 1) * sizeof(PA_Unichar)));
        require(result.fString != nullptr, "fixture string allocation");
        if (length) std::memcpy(result.fString, source, length * sizeof(PA_Unichar));
        result.fString[length] = 0;
        result.fLength = static_cast<PA_long32>(length);
        PA_Unichar* pointer = result.fString;
        strings.emplace(pointer, length);
    }
    return result;
}

void releaseString(PA_Unistring value)
{
    if (!value.fString) {
        require(value.fLength == 0, "invalid null empty disposal");
        return;
    }
    PA_Unichar* pointer = value.fString;
    require(strings.erase(pointer) == 1, "double disposal of string");
    std::free(value.fString);
}

PA_Picture makePicture()
{
    PA_Picture value = std::malloc(1);
    require(value != nullptr, "fixture picture allocation");
    pictures.emplace(value, 1);
    return value;
}

void releasePicture(PA_Picture value)
{
    if (!value) return;
    auto it = pictures.find(value);
    require(it != pictures.end() && it->second, "invalid picture release");
    if (--it->second == 0) {
        pictures.erase(it);
        std::free(value);
    }
}

void releaseHandle(PA_Handle value)
{
    if (!value) return;
    require(handles.erase(value) == 1, "invalid handle release");
    std::free(*value);
    std::free(value);
}

void clear(PA_Variable& value)
{
    switch (value.fType) {
        case eVK_Unistring: releaseString(value.uValue.fString); break;
        case eVK_Picture: releasePicture(value.uValue.fPicture); break;
        case eVK_ArrayUnicode:
            if (value.uValue.fArray.fData) {
                PA_Unistring* data = reinterpret_cast<PA_Unistring*>(*value.uValue.fArray.fData);
                for (int i = 0; i <= value.uValue.fArray.fNbElements; ++i) releaseString(data[i]);
                releaseHandle(value.uValue.fArray.fData);
            }
            break;
        case eVK_Undefined:
        case eVK_Longint: break;
        default: require(false, "unexpected variable cleanup (including raw-kind0 sentinel)");
    }
    value.fType = eVK_Undefined;
}

void balanced()
{
    if (!strings.empty() || !handles.empty() || !pictures.empty())
        std::fprintf(stderr, "outstanding strings=%zu handles=%zu pictures=%zu\n",
                     strings.size(), handles.size(), pictures.size());
    require(strings.empty(), "string owners leaked");
    require(handles.empty(), "handle owners leaked");
    require(pictures.empty(), "picture references leaked");
}

void checkPicture(PA_Picture value)
{
    require(pictures.count(value) && pictures.at(value), "owning handoff did not survive");
}

void command(EngineBlock* eb)
{
    auto args = static_cast<PA_Variable**>(eb->fPtr1);
    if (failCommand) {
        eb->fError = eER_IncompatibleTypes;
        return;
    }
    if (eb->fParam1 == 4242) {
        require(text(args[0]->uValue.fString) == expectedPath, "independent synchronous command input");
        PA_Unistring output = makeString(expectedType.c_str());
        PA_SetStringVariable(static_cast<PA_Variable*>(eb->fPtr2), &output);
        return;
    }
    switch (eb->fParam1) {
        case 678:
            require(eb->fParam2 == 2, "READ PICTURE argument count");
            require(text(args[0]->uValue.fString) == expectedPath, "exact path argument");
            clear(*args[1]);
            PA_SetPictureVariable(args[1], makePicture());
            break;
        case 1002:
            require(text(args[1]->uValue.fString) == expectedType, "exact conversion type");
            [[fallthrough]];
        case 988:
            checkPicture(PA_GetPictureVariable(*args[0]));
            if (replacePicture) {
                clear(*args[0]);
                PA_SetPictureVariable(args[0], makePicture());
            }
            break;
        case 457:
            checkPicture(PA_GetPictureVariable(*args[0]));
            PA_SetLongintVariable(args[1], 17);
            PA_SetLongintVariable(args[2], 23);
            break;
        case 679:
            checkPicture(PA_GetPictureVariable(*args[0]));
            require(PA_GetLongintVariable(*args[2]) == 17, "thumbnail width");
            require(PA_GetLongintVariable(*args[3]) == 23, "thumbnail height");
            clear(*args[1]);
            PA_SetPictureVariable(args[1], makePicture());
            break;
        default: require(false, "unexpected command (no real UI calls allowed)");
    }
    auto result = static_cast<PA_Variable*>(eb->fPtr2);
    require(result->fType == eVK_Undefined, "void commands return Undefined");
}

void host(short selector, EngineBlock* eb)
{
    switch (selector) {
        case EX_CREATE_UNISTRING:
            eb->fUniString1 = makeString(reinterpret_cast<PA_Unichar*>(eb->fHandle));
            break;
        case EX_DISPOSE_UNISTRING: releaseString(eb->fUniString1); break;
        case EX_SET_UNISTRING: {
            PA_Unistring copy = makeString(reinterpret_cast<PA_Unichar*>(eb->fHandle));
            releaseString(eb->fUniString1);
            eb->fUniString1 = copy;
            break;
        }
        case EX_CREATE_PICTURE: eb->fPicture = makePicture(); eb->fError = 0; break;
        case EX_DISPOSE_PICTURE: releasePicture(eb->fPicture); break;
        case EX_DUPLICATE_PICTURE: {
            checkPicture(eb->fPicture);
            PA_Picture picture = eb->fPicture;
            if (eb->fParam1 == 0) ++pictures.at(picture);
            else eb->fPicture = makePicture();
            break;
        }
        case EX_GET_PICTURE_DATA:
            checkPicture(eb->fPicture);
            // Metadata output ownership is not established by this bundled SDK.
            // A failed output is unusable, not an empty owning value.
            eb->fUniString1.fString = reinterpret_cast<PA_Unichar*>(1);
            eb->fUniString1.fLength = -1;
            eb->fError = eER_IncompatibleTypes;
            break;
        case EX_CLEAR_VARIABLE: clear(*static_cast<PA_Variable*>(eb->fPtr1)); break;
        case EX_HANDLE_MANAGER: {
            eb->fError = 0;
            PA_Handle handle = eb->fParam1 == 1 ? nullptr : eb->fHandle;
            switch (eb->fParam1) {
                case 1: {
                    if (failHandle) {
                        eb->fHandle = nullptr;
                        eb->fError = eER_NotEnoughMemory;
                        break;
                    }
                    eb->fHandle = static_cast<PA_Handle>(std::malloc(sizeof(char*)));
                    require(eb->fHandle != nullptr, "fixture handle allocation");
                    *eb->fHandle = static_cast<char*>(std::calloc(1, eb->fParam2 ? eb->fParam2 : 1));
                    require(*eb->fHandle != nullptr, "fixture handle data allocation");
                    handle = eb->fHandle;
                    size_t size = eb->fParam2;
                    handles.emplace(handle, size);
                    break;
                }
                case 2: releaseHandle(eb->fHandle); break;
                case 3: {
                    require(handles.count(handle), "resize valid handle");
                    void* resized = std::realloc(*eb->fHandle, eb->fParam2 ? eb->fParam2 : 1);
                    require(resized != nullptr, "fixture resize allocation");
                    *eb->fHandle = static_cast<char*>(resized);
                    handles.at(handle) = eb->fParam2;
                    break;
                }
                case 4: eb->fParam2 = handles.at(handle); break;
                case 5: eb->fParam3 = reinterpret_cast<sLONG_PTR>(*eb->fHandle); break;
                case 6: break;
                default: require(false, "unexpected handle operation");
            }
            break;
        }
        case EX_CONVERT_CHARSET_TO_CHARSET: {
            require(eb->fParam2 == eVTC_UTF_8 && eb->fParam4 == eVTC_UTF_16,
                    "conversion direction");
            CFStringRef input = CFStringCreateWithBytes(kCFAllocatorDefault,
                static_cast<UInt8*>(eb->fPtr1), eb->fParam1, kCFStringEncodingUTF8, false);
            require(input != nullptr, "valid UTF-8 fixture");
            CFIndex units = CFStringGetLength(input);
            require(eb->fParam3 >= (units + 1) * static_cast<CFIndex>(sizeof(PA_Unichar)),
                    "output capacity is bytes and includes terminator room");
            CFStringGetCharacters(input, CFRangeMake(0, units), static_cast<UniChar*>(eb->fPtr2));
            static_cast<PA_Unichar*>(eb->fPtr2)[units] = 0;
            eb->fParam3 = units * sizeof(PA_Unichar);
            eb->fError = 0;
            CFRelease(input);
            break;
        }
        case EX_EXECUTE_COMMAND_BY_ID: command(eb); break;
        case EX_CALL_BY_PROCID: {
            auto args = reinterpret_cast<PA_Variable*>(*eb->fHandle);
            require(text(args[1].uValue.fString) == expectedPath, "independent synchronous method input");
            PA_Unistring output = makeString(expectedType.c_str());
            PA_SetStringVariable(&args[0], &output);
            eb->fError = 0;
            break;
        }
        default:
            std::fprintf(stderr, "unexpected engine selector: %d\n", selector);
            std::abort();
    }
}

CUTF16String utf16(const char* source)
{
    std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> converter;
    std::u16string decoded = converter.from_bytes(source);
    return CUTF16String(decoded.begin(), decoded.end());
}

void runPicture(const std::string& name)
{
    {
        CPicture value;
        if (name == "path" || name == "path-empty") {
            for (const char* path : {"image.png", "caf\xc3\xa9.png", "\xf0\x9f\x98\x80.png", ""}) {
                if (name == "path-empty" && std::strlen(path)) continue;
                CUTF8String input(reinterpret_cast<const uint8_t*>(path));
                expectedPath = utf16(path);
                value.fromFileAtPath(&input);
                checkPicture(value.getPicture());
            }
        } else if (name == "bytes") {
            const uint8_t bytes[] = {1, 2, 3};
            value.setBytes(bytes, sizeof(bytes));
            value.setBytes(nullptr, 0);
            checkPicture(value.getPicture());
        } else if (name == "copy" || name == "copy-empty") {
            for (const char* type : {".png", ".jpg", ".tif", "caf\xc3\xa9", "\xf0\x9f\x98\x80", ""}) {
                if (name == "copy-empty" && std::strlen(type)) continue;
                expectedType = utf16(type);
                PA_Picture result = value.createCopy(type);
                checkPicture(result);
                PA_DisposePicture(result);
                checkPicture(value.getPicture());
            }
        } else if (name == "gray") {
            PA_Picture result = value.createGrayScale();
            checkPicture(result);
            PA_DisposePicture(result);
            checkPicture(value.getPicture());
        } else if (name == "size") {
            unsigned width = 0, height = 0;
            value.getSize(&width, &height);
            require(width == (failCommand || failHandle ? 0u : 17u), "picture width");
            require(height == (failCommand || failHandle ? 0u : 23u), "picture height");
            checkPicture(value.getPicture());
        } else if (name == "thumbnail") {
            PA_Picture result = value.createThumbnail(17, 23);
            checkPicture(result);
            PA_DisposePicture(result);
            checkPicture(value.getPicture());
        } else require(false, "unknown picture test");
    }
    balanced();
}

void runScalars()
{
    for (const char* fixture : {"ASCII", "caf\xc3\xa9", "\xf0\x9f\x98\x80", ""}) {
        CUTF16String expected = utf16(fixture);
        C_TEXT converted;
        converted.setUTF8String(reinterpret_cast<const uint8_t*>(fixture), std::strlen(fixture));
        CUTF16String actual;
        converted.copyUTF16String(&actual);
        require(actual == expected, "UTF-8 conversion exact independent UTF-16 oracle");
        CUTF8String roundtrip;
        converted.copyUTF8String(&roundtrip);
        require(roundtrip == CUTF8String(reinterpret_cast<const uint8_t*>(fixture)),
                "UTF-8 roundtrip exact bytes");
        require(converted.getUTF16Length() == expected.size(), "UTF-16 code-unit count");
        PA_Unistring source = PA_CreateUnistring(const_cast<PA_Unichar*>(expected.c_str()));
        C_TEXT copy;
        BytePtr parameters[] = {reinterpret_cast<BytePtr>(&source)};
        copy.fromParamAtIndex(parameters, 1);
        PA_DisposeUnistring(&source);
        CUTF16String copied;
        copy.copyUTF16String(&copied);
        require(copied == expected, "scalar input independently copied");
        PA_Unistring destination = PA_CreateUnistring(nullptr);
        parameters[0] = reinterpret_cast<BytePtr>(&destination);
        copy.toParamAtIndex(parameters, 1);
        for (int i = 0; i < 32; ++i) {
            PA_Unistring churn = PA_CreateUnistring(const_cast<PA_Unichar*>(utf16("allocator churn").c_str()));
            PA_DisposeUnistring(&churn);
        }
        require(text(destination) == expected, "scalar content setter exact value");
        PA_DisposeUnistring(&destination);
    }
    balanced();
}

void runCallbacks()
{
    for (const char* fixture : {"ASCII", "caf\xc3\xa9", "\xf0\x9f\x98\x80", ""}) {
        expectedPath = utf16(fixture);
        expectedType = utf16("owning \xf0\x9f\x98\x80 return");
        for (bool method : {false, true}) {
            PA_Unistring independent = PA_CreateUnistring(const_cast<PA_Unichar*>(expectedPath.c_str()));
            PA_Variable input = PA_CreateVariable(eVK_Undefined);
            PA_SetStringVariable(&input, &independent);
            PA_Variable result = method ? PA_ExecuteMethodByID(4242, &input, 1)
                                        : PA_ExecuteCommandByID(4242, &input, 1);
            PA_ClearVariable(&input);
            require(result.fType == eVK_Unistring, "owning callback return kind");
            require(text(result.uValue.fString) == expectedType, "return survives independent argument cleanup");
            PA_ClearVariable(&result);
        }
    }
    failHandle = true;
    PA_Variable result = PA_ExecuteCommandByID(4242, nullptr, 0);
    require(result.fType == 0, "command handle failure returns raw-kind0 sentinel");
    // Not a string despite some SDKs' normalized kind getters; never clear it.
    result = PA_ExecuteMethodByID(4242, nullptr, 0);
    require(result.fType == eVK_Undefined, "method handle failure returns Undefined");
    PA_ClearVariable(&result);
    failHandle = false;
    balanced();
}

void runArrays()
{
    PA_Variable array = PA_CreateVariable(eVK_ArrayUnicode);
    PA_ResizeArray(&array, 4);
    const char* fixtures[] = {"zero", "ASCII", "caf\xc3\xa9", "\xf0\x9f\x98\x80", ""};
    ARRAY_TEXT copy;
    for (int i = 0; i <= 4; ++i) {
        CUTF16String expected = utf16(fixtures[i]);
        PA_Unistring owned = PA_CreateUnistring(const_cast<PA_Unichar*>(expected.c_str()));
        PA_SetStringInArray(array, i, &owned);
        require(text(PA_GetStringInArray(array, i)) == expected, "array transfer content");
    }
    BytePtr parameters[] = {reinterpret_cast<BytePtr>(&array)};
    copy.fromParamAtIndex(parameters, 1);
    PA_Unistring replacement = PA_CreateUnistring(const_cast<PA_Unichar*>(utf16("replacement").c_str()));
    PA_SetStringInArray(array, 1, &replacement);
    PA_ResizeArray(&array, 0);
    PA_ClearVariable(&array);
    CUTF16String independent;
    copy.copyUTF16StringAtIndex(&independent, 3);
    require(independent == utf16(fixtures[3]), "borrowed getter copied before mutation");
    array = PA_CreateVariable(eVK_Undefined);
    copy.toParamAtIndex(parameters, 1);
    for (int i = 0; i <= 4; ++i)
        require(text(PA_GetStringInArray(array, i)) == utf16(fixtures[i]), "independent wrapper output");
    PA_Variable other = PA_CreateVariable(eVK_Undefined);
    BytePtr otherParameters[] = {reinterpret_cast<BytePtr>(&other)};
    copy.toParamAtIndex(otherParameters, 1);
    for (int i = 0; i <= 4; ++i) {
        PA_Unistring first = PA_GetStringInArray(array, i);
        PA_Unistring second = PA_GetStringInArray(other, i);
        require(text(second) == utf16(fixtures[i]), "second independent output content");
        require(!first.fString || first.fString != second.fString, "separate output allocations");
    }
    PA_ClearVariable(&other);
    copy.toParamAtIndex(parameters, 1);
    copy.setSize(1);
    copy.toParamAtIndex(parameters, 1);
    copy.setSize(0);
    copy.toParamAtIndex(parameters, 1);
    PA_ClearVariable(&array);

    array = PA_CreateVariable(eVK_ArrayUnicode);
    PA_Variable wrong = PA_CreateVariable(eVK_Longint);
    PA_Variable missing = {};
    missing.fType = eVK_ArrayUnicode;
    PA_Unistring owner = PA_CreateUnistring(const_cast<PA_Unichar*>(utf16("retained").c_str()));
    PA_SetStringInArray(wrong, 0, &owner);
    PA_SetStringInArray(missing, 0, &owner);
    PA_SetStringInArray(array, -1, &owner);
    PA_SetStringInArray(array, 1, &owner);
    PA_SetStringInArray(array, 0, nullptr);
    require(text(owner) == utf16("retained"), "rejections retain caller ownership");
    PA_DisposeUnistring(&owner);
    PA_ClearVariable(&array);
    balanced();
}

void runDispatcher()
{
    for (int endian : {0, 1}) {
        CUTF16String input = utf16("1.5");
        PA_Unistring borrowed = PA_CreateUnistring(const_cast<PA_Unichar*>(input.c_str()));
        BytePtr parameters[] = {reinterpret_cast<BytePtr>(&borrowed), reinterpret_cast<BytePtr>(&endian)};
        PA_Handle result = nullptr;
        FourDPackex(2, parameters, nullptr, &result);
        const unsigned char little[] = {0, 0, 0xc0, 0x3f};
        const unsigned char big[] = {0x3f, 0xc0, 0, 0};
        require(PA_GetHandleSize(result) == 4, "dispatcher BLOB length");
        require(std::memcmp(*result, endian ? big : little, 4) == 0, "dispatcher exact float bytes");
        require(text(borrowed) == input, "dispatcher input remains borrowed");
        int mode = 0, precision = -1;
        BytePtr back[] = {reinterpret_cast<BytePtr>(&result), reinterpret_cast<BytePtr>(&mode),
                         reinterpret_cast<BytePtr>(&endian), reinterpret_cast<BytePtr>(&precision)};
        PA_Unistring output = PA_CreateUnistring(nullptr);
        PA_Unistring* outputPtr = &output;
        FourDPackex(1, back, nullptr, &outputPtr);
        require(text(output) == utf16("2"), "dispatcher scalar content setter survives local destruction");
        PA_DisposeUnistring(&output);
        PA_DisposeUnistring(&borrowed);
        PA_DisposeHandle(result);
    }
    balanced();
}
}

int main(int argc, char** argv)
{
    require(argc >= 2, "test name required");
    gCall4D = host;
    require(utf16("\xf0\x9f\x98\x80") == CUTF16String({0xd83d, 0xde00}), "supplementary fixture surrogate pair");
    require(utf16("caf\xc3\xa9") == CUTF16String({'c', 'a', 'f', 0xe9}), "BMP fixture exact units");
    nullEmpty = argc > 2 && std::string(argv[2]) == "null-empty";
    failHandle = argc > 2 && std::string(argv[2]) == "fail-handle";
    failCommand = argc > 2 && std::string(argv[2]) == "fail-command";
    replacePicture = !(argc > 2 && std::string(argv[2]) == "unchanged");
    std::string name = argv[1];
    if (name == "arrays") runArrays();
    else if (name == "scalars") runScalars();
    else if (name == "callbacks") runCallbacks();
    else if (name == "dispatcher") runDispatcher();
    else runPicture(name);
    std::printf("PASS %s %s\n", argv[1], argc > 2 ? argv[2] : "allocated-empty");
}
