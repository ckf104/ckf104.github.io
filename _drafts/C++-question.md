* 函数中的静态变量的初始化时间？全局变量的初始化时间？
* 线程私有变量的初始化和析构时间？
* 类成员定义时给予默认值是怎么实现的



* name lookup rules ? assignment operator inheritance ?
* 为什么隐式转换不能通过，因为参数是模板？

```c++
#include <iostream>
#include <string>

using namespace std;

struct F{
    string f;
    operator string (){
        return f;
    }
};
template string std::operator+(const string&, const string&);
/*
string operator+(const string& a, const string& b){
        return std::operator+(a, b);
}
*/
int main()
{
  /*  
        string g("aa");
    F f;
    f.f = string("bb");
    cout << f + g << endl;
        */
    return 0;
}

```

