
#include "Package1_HelloWorld.hpp"
#include "Tpl1.hpp"

std::string Package1::deps()
{
  std::string deps;
  deps = Tpl1::itsme();
  return deps;
}
