---
title: 从 Unicode 到 locale -- 理解 C++ 中的编码边界
date: 2026-04-24 15:24:51 +0800
comments: true
categories:
  - cpp
  - misc
---
很多“乱码”问题并不是某一种编码坏掉了，而是几个层次被混在了一起。`Unicode` 负责定义字符，`UTF` 负责把字符编码成 `code unit` 序列，`locale` 负责告诉运行库如何解释和格式化文本，而 terminal 最终决定这些 bytes 会怎样显示

如果把这几个层次拆开看，很多表面上神秘的问题其实都能顺着链路定位。下面按从抽象到实现的顺序，把 `Unicode`、`locale`、`charmap` 以及 C / C++ 中的字符模型连起来讲清楚

## 1. Unicode 与 UTF

`Unicode` 首先是一套字符编号体系。它给每个抽象字符分配一个 `code point`，例如字符 `é` 的 `code point` 是 `U+00E9`，汉字 `你` 的 `code point` 是 `U+4F60`

但 `Unicode` 本身不规定这些 `code point` 在内存或文件里一定怎样排布。真正决定存储方式的是 `UTF-8`、`UTF-16` 和 `UTF-32` 这些 `Unicode Transformation Format`。它们描述的是如何把同一个 `code point` 编码成不同长度的 `code unit` 序列

以 `é` 为例，它的 `code point` 是 `U+00E9`。如果把这个值写成二进制，可以得到 `11101001`。`UTF-8` 规定 `U+0080` 到 `U+07FF` 范围内的字符使用两个字节，模板是 `110xxxxx 10xxxxxx`。把 `U+00E9` 补到 11 位得到 `00011101001`，再拆成 `00011` 和 `101001`，填入模板后就是 `11000011 10101001`，也就是 `0xC3 0xA9`

所以 `U+00E9` 和 `C3 A9` 不是两个互相竞争的结果，而是两个不同层次的描述。前者是抽象字符编号，后者是这个编号在 `UTF-8` 下的字节表示。换成 `UTF-16` 时它会变成一个 16 位 `code unit`，换成 `UTF-32` 时则会变成一个 32 位 `code unit`

理解这一点很重要，因为工程里的很多讨论其实都在混用三个概念，也就是 `character`、`code point` 和 `code unit`。如果不把它们区分开，就很容易把“一个字符占几个字节”说成一句没有上下文就无法判断真假的话

## 2. locale 与 charmap

在 glibc 体系里，`locale` 和 `charmap` 是两个相关但并不相同的概念

`locale` 描述的是一整套地区化规则，包括字符分类、大小写转换、排序规则、日期时间格式、数字格式、货币格式等内容。它通常按 `LC_CTYPE`、`LC_COLLATE`、`LC_TIME`、`LC_NUMERIC` 这类 category 拆开定义，因此它解决的并不只是编码问题，而是整个本地化行为的问题

`charmap` 描述的则是字符集与外部字节表示之间的映射关系，也就是某个 `multibyte encoding` 的具体定义。你可以把它理解成“外部世界的 bytes 应该如何还原成字符”的那份规则文件，它更接近编码层，而不是文化习惯层

在常见 Linux 发行版的 glibc 数据目录下，这两类输入通常分别位于下面两个位置

- `/usr/share/i18n/locales/`
- `/usr/share/i18n/charmaps/`

前者提供诸如 `zh_CN`、`en_US` 这样的 locale definition，后者提供诸如 `UTF-8`、`GB18030` 这样的 charmap definition

真正让系统可用的 locale 往往不是直接读取这两个文本文件，而是先用 `localedef` 把它们编译成运行时可加载的 locale 数据

```bash
localedef -i zh_CN -f GB18030 zh_CN.GB18030
```

这条命令里的 `-i zh_CN` 选择 locale definition，`-f GB18030` 选择 charmap definition，最后生成一个名为 `zh_CN.GB18030` 的 compiled locale。之后 `setlocale` 或 `std::locale("zh_CN.GB18030")` 才能在运行时按这个名字加载它

很多人第一次看到 `sudo locale-gen zh_CN.GB18030` 会误以为它只是在“安装一个编码”。更准确的理解是，它让系统生成一个 locale 实例，这个实例一方面继承 `zh_CN` 的地区化规则，另一方面使用 `GB18030` 作为外部字符编码。在 Debian 和 Ubuntu 一类发行版上，`locale-gen` 往往只是围绕 `localedef` 做的一层脚本封装，不同发行版参数细节可能略有差异，但底层思路基本一致

也就是说，`zh_CN.GB18030` 这种名字本身就已经在暗示两个维度。`zh_CN` 说明“按中文地区习惯工作”，`GB18030` 说明“和外部字节流交互时使用 GB18030 编码”

## 3. C / C++ 中的字符类型与字面量

进入语言层之后，问题又要再拆成两部分来看，一部分是程序内部用什么类型保存字符，另一部分是字面量在编译时会被编码成什么形式

先看最常见的字符类型和 literal prefix

| 类型 | 常见字面量形式 | 典型含义 |
| --- | --- | --- |
| `char` | `"abc"` 或 `'a'` | ordinary character type |
| `wchar_t` | `L"abc"` 或 `L'a'` | wide character type |
| `char8_t` | `u8"abc"` | UTF-8 code unit type |
| `char16_t` | `u"abc"` | UTF-16 code unit type |
| `char32_t` | `U"abc"` | UTF-32 code unit type |

在 C 里，最核心的是 `char` 和 `wchar_t`。在 C++ 里，又额外引入了 `char8_t`、`char16_t` 和 `char32_t`，让 UTF 编码的意图可以在类型层面表达得更清楚。需要额外注意的是，在 C++20 之后，`u8"..."` 的元素类型是 `char8_t`，不再是 `char`

其中最容易误解的是 `wchar_t`。它不是“总能容纳一个 Unicode 字符”的神奇类型，而是一个 implementation-defined 的 wide character type。实际工程里，Linux 和许多非 Windows 系统上常见的是 32 位 `wchar_t`，通常保存 `UTF-32 code unit`；Windows 上常见的是 16 位 `wchar_t`，通常保存 `UTF-16 code unit`。这也是为什么同一段 `std::wstring` 代码跨平台后，`size()` 可能并不相同

因此更稳妥的理解方式是，`char16_t` 和 `char32_t` 对应的是明确的编码宽度，`wchar_t` 对应的是平台自己的 wide character model。它在某些平台上碰巧接近 `UTF-32`，在另一些平台上则更接近 `UTF-16`

对应的字符串类型也就分别是 `std::string`、`std::wstring`、`std::u8string`、`std::u16string` 和 `std::u32string`

标准库对 `char` 和 `wchar_t` 提供了成体系的文本输入输出接口，因此常把它们对应的流称为 `narrow stream` 和 `wide stream`。对于 `char8_t`、`char16_t` 和 `char32_t`，标准库目前并没有对等的通用文本 stream 类型，工程里通常需要显式转码，或者先把它们当作 `code unit` 容器处理

下面这段程序很适合把“同一段文本在不同编码下占用多少 `code unit`”直观地打印出来

```c++
#include <iostream>
#include <string>

template <typename StringT>
void print_encoding_storage(const StringT& str, const char* name) {
    using CharT = typename StringT::value_type;
    std::cout << name
              << " code units: " << str.size()
              << ", bytes per unit: " << sizeof(CharT)
              << ", total bytes: " << str.size() * sizeof(CharT)
              << '\n';
}

int main() {
    std::string s = "你好呀😊";
    std::u16string s16 = u"你好呀😊";
    std::u32string s32 = U"你好呀😊";
    std::wstring ws = L"你好呀😊";

    print_encoding_storage(s, "ordinary literal in std::string");
    print_encoding_storage(s16, "UTF-16 in std::u16string");
    print_encoding_storage(s32, "UTF-32 in std::u32string");
    print_encoding_storage(ws, "wide literal in std::wstring");
}
```

如果 ordinary literal 的 `execution character set` 恰好是 `UTF-8`，那么 `"你好呀😊"` 在 `std::string` 里通常会占 13 个字节，也就是 13 个 8 位 `code unit`。`std::u16string` 会得到 5 个 `code unit`，因为表情符号需要一个 surrogate pair。`std::u32string` 会得到 4 个 `code unit`。至于 `std::wstring`，Linux 上常见结果是 4，Windows 上则常见结果是 5

这个例子也顺便说明了一件事，字符串容器里存的并不是“字符个数”，而是某种编码下的 `code unit` 序列。只有在特定编码语义下，`size()` 才能被进一步解释成接近“字符数量”的东西

## 4. 编译期的编码边界

很多编码问题其实在程序运行之前就已经决定了一半，因为编译器必须先把源文件里的字面量解释出来

这里最值得分清的是 `source character set` 和 `execution character set`

- `source character set` 指源文件是以什么编码存储，并被编译器按什么方式解码
- `execution character set` 指 ordinary character literal 和 ordinary string literal 在编译结果里会被编码成什么形式
- `wide execution character set` 则影响 `L"..."` 这类 wide literal 的内部表示

如果源文件本身是 `UTF-8`，编译器也按 `UTF-8` 解释它，那么源代码里的 `"你好"` 才有机会被正确识别成两个 Unicode 字符。接下来，编译器还要把这个 ordinary literal 转成 `execution character set`。如果 `execution character set` 仍然是 `UTF-8`，那 `std::string` 里的 bytes 看起来就像大家熟悉的 UTF-8 文本。可如果 `execution character set` 被设成别的编码，同样的源码字面量进入程序后就可能已经不是 UTF-8 了

这也是为什么“源码文件明明保存成了 UTF-8，为什么程序输出还是乱码”这个问题往往不能只盯着编辑器。源码编码、编译器对字面量的编码策略、运行时 locale、终端期望的外部编码，这四层只要有一层不一致，最后看到的结果就可能出问题

## 5. 运行期的编码边界

进入运行期之后，重点从“字面量如何进入程序”变成“程序如何与外部 bytes 交互”

这里可以先抓住一条总规律

- `char` 相关接口通常把 bytes 当作 bytes 处理
- `wchar_t` 相关接口通常会在 `wchar_t` 与外部 `multibyte sequence` 之间做转换，这个转换规则由当前 `locale` 决定，与文件的打开模式（binary/text mode）无关
- terminal 最终仍会按自己的编码假设去解释收到的 bytes

也就是说，`std::cout` 输出 `std::string` 时，通常不会额外帮你做“把 UTF-8 转成别的编码”这一步。它更像是把容器里的 bytes 原样送到外部设备。而 `std::wcout`、`fwprintf` 这类 wide character 接口则会调用 locale 相关的转换逻辑，把内部的 `wchar_t` 序列编码成外部 `multibyte sequence`

## 6. C 的 locale 环境

C 语言的 locale 模型比较直接，它本质上依赖一个全局的 C locale。程序启动时，运行库等价于先执行了一次 `setlocale(LC_ALL, "C")`，也就是默认处在经典的 `C locale`

这意味着如果你什么都不做，很多和本地化相关的行为都按最保守的 `C` 规则运行，其中也包括 wide character 与 multibyte 之间的转换行为

C 标准库里的 `FILE stream` 还有一个很关键的概念叫 orientation。一个流在刚创建时还没有定向，第一次使用 narrow I/O 还是 wide I/O 会把它固定成 `narrow-oriented` 或 `wide-oriented`。之后除非 `freopen`，否则这个定向不会改变

一旦流变成 `wide-oriented`，运行库就会在 `wchar_t` 与外部 `multibyte` 表示之间做转换，这个过程可以理解为内部调用 `mbrtowc` 和 `wcrtomb`，并由 `FILE stream` 内部的 `mbstate_t` 维护状态（[What is mbstate_t and why to reset it?](https://stackoverflow.com/questions/70432999/what-is-mbstate-t-and-why-to-reset-it) 中讨论了为什么需要一个 `mbstate_t`）。更重要的是，流的转换状态是在它被定向为 `wide-oriented` 的那一刻，按照当时安装的 C locale 建立起来的。因此，如果先让 `stdout` 以 wide 方式工作，后面再去改 `setlocale`，新 locale 不一定会自动重建这个流已经建立好的转换状态。对 C 风格 I/O 来说，locale 的安装时机和流的首次使用顺序同样重要

## 7. C++ 的 locale 环境

C++ 在 C 的基础上多了一层 `std::locale` 抽象。和 C 只有一个全局 locale 不同，C++ 的 stream 可以各自携带 locale object，并通过 `imbue` 单独修改。例如

```c++
#include <iostream>
#include <locale>

int main() {
    std::cout << 1234.56 << '\n'; // 1234.56

    std::locale us("en_US.UTF-8");
    std::cout.imbue(us);
    std::cout << 1234.56 << '\n'; // 1,234.56
}
```

上面的例子里，变化的并不是字符串字节编码，而是 `std::num_put` 之类 locale facet 参与的格式化规则。这一点很值得和“编码转换”分开看，否则很容易把所有 locale 行为都笼统地理解成字符集切换

对于 wide stream，C++ 通过 locale 中的 `std::codecvt<CharT, char, std::mbstate_t>` facet 在内部字符类型与外部 bytes 之间做转换。默认的全局 C++ locale 仍然是 `C`，所以在很多实现里，`std::wcout` 默认并不能正确输出非 ASCII 内容

一个常见做法是在程序开始时把全局 locale 切到系统当前环境

```c++
#include <iostream>
#include <locale>
#include <string>

int main() {
    std::locale::global(std::locale(""));

    std::wstring ws = L"你好呀y😊";
    std::wcout << ws << '\n';
}
```

`std::locale("")` 的含义是“按系统当前环境变量加载 locale”。调用 `std::locale::global` 后，后续新建的 C++ stream 会把这个 locale 作为默认值，而且当 locale 名称非空时，它还会同步影响底层的 C locale

虽然在上一个例子中 wcout 内部的 locale 仍然是 C，但由于 iostream 的输出会同步给 stdio 的 stream buffer，因此只修改全局的 locale 就起作用了。但如果关闭了 iostream 和 stdio 的同步，那么就使用 `imbue` 直接给 `std::wcout` 设置 locale

```c++
#include <iostream>
#include <locale>
#include <string>

int main() {
    std::ios::sync_with_stdio(false);
    std::wcout.imbue(std::locale(""));

    std::wstring ws = L"你好呀y😊";
    std::wcout << ws << '\n';
}
```

这里 `std::wcout` 会按它自己的 locale 把 `wchar_t` 转成外部 `multibyte sequence`。如果这个 locale 是 `en_US.UTF-8` 或 `zh_CN.UTF-8`，而 terminal 也按 UTF-8 解码，那么输出通常就能正常显示

那如果我们将 locale 设置为与 UTF-8 不兼容的 GB18030，terminal 按照 UTF-8 去解码 GB18030 格式的编码，输出就会显式为乱码

```c++
#include <iostream>
#include <locale>
#include <string>

int main() {
    std::ios::sync_with_stdio(false);
    std::wcout.imbue(std::locale("zh_CN.GB18030"));

    std::wstring ws = L"你好呀y😊";
    std::wcout << ws << '\n';
}
```

## 8. 总结

把 `Unicode`、`UTF`、`locale` 和 C / C++ 的 I/O 模型放在同一张图里看，逻辑就会清楚很多

`Unicode` 解决的是字符编号问题，`UTF` 解决的是编号如何落到 `code unit` 和 bytes 上，`locale` 解决的是运行库在本地化和字符转换时应采用什么规则，而 terminal 决定最后这些 bytes 被怎样渲染成屏幕上的字形

编码问题的排查包含四层

- 程序内部字符串到底是什么编码或什么字符类型
- 编译器把字面量编译成了什么
- 运行时 locale 期望输出什么外部编码
- terminal 最终按什么编码解释这些 bytes

只要这四层有一层不匹配，最终用户看到的现象就可能统称为“乱码”，但真正的问题位置并不相同

因此讨论“编码”时，最有价值的习惯不是立刻问“它是不是 UTF-8”，而是先问自己当前说的是哪一层，是 source file、literal encoding、internal string representation、runtime locale，还是 terminal decoding。只要层次一旦分清，大多数看似绕人的问题都会重新变得可以推导

## 参考资料

- [cppreference `Fundamental types`](https://en.cppreference.com/cpp/language/types)
- [cppreference `std::setlocale`](https://en.cppreference.com/cpp/locale/setlocale)
- [cppreference `std::locale::global`](https://en.cppreference.com/cpp/locale/locale/global)
- [cppreference `FILE`](https://en.cppreference.com/w/c/io/FILE)
- [man7 `localedef(1)`](https://man7.org/linux/man-pages/man1/localedef.1.html)
- [Debian `locale-gen(8)`](https://manpages.debian.org/bookworm/locales/locale-gen.8.en.html)