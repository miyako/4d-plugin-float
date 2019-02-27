# 4d-plugin-float
Convert float32 data to text and back

## Platform

| carbon | cocoa | win32 | win64 |
|:------:|:-----:|:---------:|:---------:|
|||<img src="https://cloud.githubusercontent.com/assets/1725068/22371562/1b091f0a-e4db-11e6-8458-8653954a7cce.png" width="24" height="24" />|<img src="https://cloud.githubusercontent.com/assets/1725068/22371562/1b091f0a-e4db-11e6-8458-8653954a7cce.png" width="24" height="24" />|

### Version

<img src="https://cloud.githubusercontent.com/assets/1725068/18940649/21945000-8645-11e6-86ed-4a0f800e5a73.png" width="32" height="32" /> <img src="https://cloud.githubusercontent.com/assets/1725068/18940648/2192ddba-8645-11e6-864d-6d5692d55717.png" width="32" height="32" /> <img src="https://user-images.githubusercontent.com/1725068/41266195-ddf767b2-6e30-11e8-9d6b-2adf6a9f57a5.png" width="32" height="32" />

![preemption xx](https://user-images.githubusercontent.com/1725068/41327179-4e839948-6efd-11e8-982b-a670d511e04f.png)

## Syntax

```
float:=BLOB to float (bytes{;format{;precision}})
```

Parameter|Type|Description
------------|------------|----
float|TEXT|
bytes|BLOB|
format|LONGINT|
precision|LONGINT|

#### Float formats

* ``Float scientific notation``: ``%e`` format of ``printf()``  
* ``Float decimal floating point``: ``%f`` format of ``printf()`` (default)  
* ``Float shortest format``: ``%g`` format of ``printf()``  

#### Float endianness

* ``Float little endian``: native byte order for i386, x86_64 (default)
* ``Float big endian``: native byte order for ppc    

#### Float precision

* ``Float precision default``: number pass to ``.*`` format of ``printf()``  

**Note**: ``-1`` is the default (``FLT_DECIMAL_DIG - 1`` or ``5``)