#include <math.h>
int main(int argc, char** argv) {
    (void)argv;
    volatile double x = (double)argc + 0.25;
    return (int)(sqrt(x) + cos(x) + sin(x));
}
