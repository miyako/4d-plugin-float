/* --------------------------------------------------------------------------------
 #
 #	4DPlugin.cpp
 #	source generated by 4D Plugin Wizard
 #	Project : Float
 #	author : miyako
 #	2019/02/27
 #
 # --------------------------------------------------------------------------------*/


#include "4DPluginAPI.h"
#include "4DPlugin.h"

void PluginMain(PA_long32 selector, PA_PluginParameters params)
{
	try
	{
		PA_long32 pProcNum = selector;
		sLONG_PTR *pResult = (sLONG_PTR *)params->fResult;
		PackagePtr pParams = (PackagePtr)params->fParameters;

		CommandDispatcher(pProcNum, pResult, pParams); 
	}
	catch(...)
	{

	}
}

void CommandDispatcher (PA_long32 pProcNum, sLONG_PTR *pResult, PackagePtr pParams)
{
	switch(pProcNum)
	{
// --- IEEE 754

		case 1 :
			BLOB_to_float(pResult, pParams);
			break;

		case 2 :
			float_to_BLOB(pResult, pParams);
			break;

	}
}

// ----------------------------------- IEEE 754 -----------------------------------


void BLOB_to_float(sLONG_PTR *pResult, PackagePtr pParams)
{
	C_BLOB Param1;
	C_LONGINT Param2;
	C_LONGINT Param3;
    C_LONGINT Param4;
	C_TEXT returnValue;

	Param1.fromParamAtIndex(pParams, 1);
	Param2.fromParamAtIndex(pParams, 2);
	Param3.fromParamAtIndex(pParams, 3);
    Param4.fromParamAtIndex(pParams, 4);
    
    float_size_t size = Param1.getBytesLength();
    float_convert_mode_t mode = (float_convert_mode_t)Param2.getIntValue();
    float_string_length_t len;
    float_precision_t precision = Param4.getIntValue();
    float_endian_t endian = (float_endian_t)Param3.getIntValue();
    
    switch (precision) {
        case -1:
            precision = 0;
            break;
        case  0:
            precision = float_precision_default;
            break;
        default:
            break;
    }
    
    switch (size) {
        case sizeof(float):
        {
            std::vector<uint8_t>bytes(sizeof(float));
            memset((void *)&bytes[0], 0x0, sizeof(float));
            float f32 = 0.0f;
           
            std::vector<uint8_t>buf(sizeof(float));
            memcpy(&buf[0], Param1.getBytesPtr(), sizeof(float));
           
            switch (endian) {
                case float_endian_big:
                {
                    
                    bytes[0] = buf[3];
                    bytes[1] = buf[2];
                    bytes[2] = buf[1];
                    bytes[3] = buf[0];
                }
                    break;
                default:
                    memcpy((void *)&bytes[0], &buf[0], sizeof(float));
                    break;
            }
            
            memcpy(&f32, &bytes[0], sizeof(float));

            switch (mode) {
                case float_convert_mode_e:
                {
                    len = snprintf(0, 0, float_fmt_e, precision, f32);
                    std::vector<uint8_t>buf(len + 1);
                    snprintf((char *)&buf[0], buf.size(), float_fmt_e, precision, f32);
                    returnValue.setUTF8String(&buf[0],len);
                }
                    break;
                case float_convert_mode_f:
                {
                    len = snprintf(0, 0, float_fmt_f, precision, f32);
                    std::vector<uint8_t>buf(len + 1);
                    snprintf((char *)&buf[0], buf.size(), float_fmt_f, precision, f32);
                    returnValue.setUTF8String(&buf[0],len);
                }
                    break;
                case float_convert_mode_g:
                {
                    len = snprintf(0, 0, float_fmt_g, precision, f32);
                    std::vector<uint8_t>buf(len + 1);
                    snprintf((char *)&buf[0], buf.size(), float_fmt_g, precision, f32);
                    returnValue.setUTF8String(&buf[0],len);
                }
                    break;
                default:
                    break;
            }
            
        }
            break;
            
        default:
            break;
    }

	returnValue.setReturn(pResult);
}

void float_to_BLOB(sLONG_PTR *pResult, PackagePtr pParams)
{
	C_TEXT Param1;
	C_LONGINT Param2;
	C_BLOB returnValue;

	Param1.fromParamAtIndex(pParams, 1);
	Param2.fromParamAtIndex(pParams, 2);

    std::vector<uint8_t>bytes(sizeof(float));
    memset((void *)&bytes[0], 0x0, sizeof(float));
    float f32 = 0.0f;
    
    float_endian_t endian = (float_endian_t)Param2.getIntValue();
    
    CUTF8String s;
    Param1.copyUTF8String(&s);
    
    if(s.length()){
        f32 = strtof((const char *)s.c_str(), NULL);
        std::vector<uint8_t>buf(sizeof(float));
        memcpy((void *)&buf[0], &f32, sizeof(float));
        
        switch (endian) {
            case float_endian_big:
            {
                
                bytes[0] = buf[3];
                bytes[1] = buf[2];
                bytes[2] = buf[1];
                bytes[3] = buf[0];
            }
                break;
            default:
                memcpy((void *)&bytes[0], &buf[0], sizeof(float));
                break;
        }
    }
    
    returnValue.setBytes((const uint8_t *)&bytes[0], sizeof(float));
	returnValue.setReturn(pResult);
}

