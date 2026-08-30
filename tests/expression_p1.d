module tests.expression_p1;

import core.stdc.math : fabs;
import core.stdc.string : strcmp;
import waifucad.kernel.expressions : evaluateExpression, ExpressionValue, WC_EXPRESSION_DOMAIN, WC_EXPRESSION_UNIT_MISMATCH;
import waifucad.kernel.types : Unit;

private bool lookup(void*, const(char)* name, double* value, Unit* unit) nothrow @nogc
{
    if(strcmp(name,"width".ptr)==0){*value=80.0;*unit=Unit.millimetre;return true;}
    return false;
}
private bool near(double a,double b) nothrow @nogc{return fabs(a-b)<=1.0e-8;}

extern(C) int main()
{
    auto trig=evaluateExpression("sin(30 deg)".ptr,&lookup,null,Unit.unitless);if(trig.error!=0||!near(trig.value,0.5))return 10;
    auto clamped=evaluateExpression("clamp(width / 2, 20 mm, 30 mm)".ptr,&lookup,null,Unit.millimetre);if(clamped.error!=0||!near(clamped.value,30.0))return 11;
    auto angle=evaluateExpression("atan2(1, 1)".ptr,&lookup,null,Unit.degree);if(angle.error!=0||!near(angle.value,45.0))return 12;
    auto root=evaluateExpression("sqrt(9)".ptr,&lookup,null,Unit.unitless);if(root.error!=0||!near(root.value,3.0))return 13;
    auto domain=evaluateExpression("sqrt(-1)".ptr,&lookup,null,Unit.unitless);if(domain.error!=WC_EXPRESSION_DOMAIN)return 14;
    auto units=evaluateExpression("min(width, 1 deg)".ptr,&lookup,null,Unit.millimetre);if(units.error!=WC_EXPRESSION_UNIT_MISMATCH)return 15;
    return 0;
}

