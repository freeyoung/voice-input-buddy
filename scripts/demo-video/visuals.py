from PIL import Image, ImageDraw, ImageFont
import math, re
W,H,FPS=1920,1080,12
FONT='/System/Library/Fonts/STHeiti Medium.ttc'
fonts={s:ImageFont.truetype(FONT,s) for s in [20,24,28,32,36,40,48,54,64,80]}
BLUE='#3268DA'; INK='#253449'; GREEN='#35AB84'; ORANGE='#EF9C4C'; BG='#FFF9EF'; LINE='#DCE3EE'
scenes=[
 ('语音搭子', '让语音更强大', ['拿起遥控器', '按住说话', '松开，输入文字'], ''),
 ('它是怎样工作的？', '连接设备，也连接你常用的输入工具', ['遥控器：收集声音和按键', '语音搭子：传送音频、映射快捷键', '输入工具：识别并输入文字'], ''),
 ('01  安装一次，就准备好', '一个 PKG，安装 App 和虚拟麦克风驱动', ['前往 voice.zfdang.com', '下载 macOS 安装包', '安装后打开 Voice Input Buddy'], ''),
 ('02  权限与环境', '跟随设置向导，逐项检查', ['蓝牙权限：连接遥控器', '输入监控：读取遥控器按键', '辅助功能：模拟语音快捷键'], ''),
 ('03  连接你的遥控器', '以小米蓝牙遥控器 2 Pro 为例', ['让遥控器进入蓝牙配对状态', '按向导完成配对和连接', '确认设备已连接'], ''),
 ('04  让声音去对地方', '两个工具，选择同一个虚拟麦克风', ['语音搭子：选择语音输出', '输入工具：选择语音输入麦克风', '先试音；声音偏小再调整增益'], ''),
 ('05  按键映射', '常用操作，一键直达', ['在下拉框中选择遥控器', '点选按键，再设置动作', '单击、双击、长按分别配置'], ''),
 ('06  输入法与语音工具集成', '以微信输入法为例', ['选择微信输入法', '核对 Fn 语音快捷键', '按图设置，再进行语音测试'], ''),
 ('试一试：按住，说话，松开', '把光标放进输入框，然后使用语音键', ['点击你要输入的位置', '按住语音键，说一句话', '松开，等待输入工具返回文字'], ''),
 ('准备好了，开始使用吧', 'voice.zfdang.com', ['没有声音？核对连接和两侧麦克风', '按键无效？检查权限和快捷键冲突', '设置里可重新运行向导、检查更新'], ''),
]

def text(d,xy,t,size=36,fill=INK): d.text(xy,t,font=fonts[size],fill=fill)
def rr(d,box,fill,r=28,outline=None,width=2): d.rounded_rectangle(box,radius=r,fill=fill,outline=outline,width=width)
def center(d,x,y,t,size=36,color=INK):
 b=d.textbbox((0,0),t,font=fonts[size]); text(d,(x-(b[2]-b[0])/2,y),t,size,color)
def wrap(d,t,size,maxw):
 lines=[]; s=''
 for c in t:
  if d.textlength(s+c,font=fonts[size])>maxw: lines.append(s);s=c
  else:s+=c
 if s:lines.append(s)
 return lines

def character(d,x,y,t):
 # Friendly cartoon operator, drawn directly for this animation.
 bob=math.sin(t*2.4)*4
 y+=bob
 d.ellipse((x-92,y-78,x+92,y+114),fill='#E6BE98',outline=INK,width=4)
 d.pieslice((x-94,y-100,x+94,y+73),180,360,fill='#364358')
 d.ellipse((x-51,y+1,x-35,y+22),fill=INK);d.ellipse((x+32,y+1,x+48,y+22),fill=INK)
 d.ellipse((x-77,y+40,x-49,y+52),fill='#E8998D');d.ellipse((x+48,y+40,x+76,y+52),fill='#E8998D')
 d.arc((x-29,y+18,x+29,y+64),5,175,fill=INK,width=5)
 rr(d,(x-122,y+112,x+122,y+320),BLUE,60)
 d.line((x-84,y+170,x-150,y+232),fill='#E6BE98',width=36)
 d.line((x+82,y+170,x+156,y+112),fill='#E6BE98',width=36)
 d.ellipse((x+130,y+88,x+174,y+131),fill='#E6BE98',outline=INK,width=3)
 text(d,(x-52,y+165),'VIB',48,'white')

def remote(d,x,y,t,active=False,scale=1):
 rw,rh=int(112*scale),int(310*scale)
 if scale != 1:
  layer=Image.new('RGBA',(112,310),(0,0,0,0))
  remote(ImageDraw.Draw(layer),0,0,t,active,1)
  layer=layer.resize((rw,rh),Image.Resampling.LANCZOS)
  d._image.paste(layer,(int(x),int(y)),layer)
  return
 rr(d,(x,y,x+rw,y+rh),'#344256',30)
 for px in [.31,.70]: d.ellipse((x+rw*px-10,y+28,x+rw*px+10,y+48),fill='#647489')
 if active:
  d.ellipse((x+rw*.70-16,y+22,x+rw*.70+16,y+54),outline=GREEN,width=5)
 d.ellipse((x+rw*.18,y+65,x+rw*.82,y+139),fill='#1F2C40')
 d.ellipse((x+rw*.38,y+89,x+rw*.62,y+114),fill='#728296')
 for row in range(3):
  for px in [.32,.68]:d.ellipse((x+rw*px-10,y+161+row*39,x+rw*px+10,y+181+row*39),fill='#728296')
 center(d,x+rw/2,y+rh-26,'VIB',24,'#AAB8CA')

def window(d,selected,t):
 rr(d,(960,236,1780,836),'white',30,LINE,3)
 rr(d,(960,236,1780,287),'#E9EFF8',26)
 for i,c in enumerate(['#F57E73','#F3C264','#81CFA5']):d.ellipse((984+i*28,252,999+i*28,267),fill=c)
 center(d,1370,249,'语音搭子',24)
 rr(d,(960,288,1120,836),'#F2F6FD',12)
 nav=['设备连接','按键映射','输入法集成','权限与环境','设置']
 for j,n in enumerate(nav):
  yy=318+j*82
  if j==selected:rr(d,(973,yy-10,1106,yy+50),'#DCE9FF',12)
  center(d,1040,yy,n,24,BLUE if j==selected else '#7A869A')
 return 1160,316

def frame(i,u,total):
 im=Image.new('RGB',(W,H),BG);d=ImageDraw.Draw(im)
 # Deliberately restrained motion, large text, and consistent cartoon palette.
 for j in range(5):
  xx=1500+j*90; yy=90+math.sin(u*.4+j)*18
  d.ellipse((xx,yy,xx+28,yy+28),fill='#E1EBFA')
 text(d,(92,43),'VOICE INPUT BUDDY  /  语音搭子',28,BLUE)
 text(d,(92,112),scenes[i][0],64)
 text(d,(94,198),scenes[i][1],32,'#758398')
 rr(d,(92,282,860,835),'#EDF3FC',36)
 character(d,270,450,u)
 for j,line in enumerate(scenes[i][2]):
  yy=329+j*113
  if u>j*.65:
   d.ellipse((440,yy+2,478,yy+40),fill=GREEN)
   center(d,459,yy+3,str(j+1),28,'white')
   ls=wrap(d,line,32,335)
   for k,l in enumerate(ls):text(d,(497,yy+k*41),l,32)
 # Scene-specific animated demo on the right.
 if i==0:
  remote(d,1130,360,u,2<u<8,1.4)
  rr(d,(1370,389,1780,650),'white',30,LINE)
  center(d,1575,445,'按住说话',48,BLUE)
  center(d,1575,528,'松开后，文字出现',28)
 elif i==1:
  labels=['遥控器','语音搭子','输入工具']
  for j,l in enumerate(labels):
   xx=930+j*293
   rr(d,(xx,421,xx+255,646),'white',26,LINE)
   center(d,xx+127,456,['声音','连接桥梁','文字'][j],48,BLUE)
   center(d,xx+127,553,l,32)
   if j<2:
    d.line((xx+260,527,xx+288,527),fill=GREEN,width=6)
  pos=930+(u%3)/3*840;d.ellipse((pos,704,pos+24,728),fill=GREEN)
 elif i==2:
  rr(d,(1030,317,1740,763),'white',36,LINE)
  center(d,1385,365,'Voice_Input_Buddy.pkg',40,BLUE)
  for j,l in enumerate(['Voice Input Buddy.app','虚拟麦克风驱动']):
   rr(d,(1100,450+j*105,1670,527+j*105),'#EDF3FC',18)
   center(d,1385,467+j*105,l,32)
  center(d,1385,683,'一个安装包，完成两项安装',28)
 elif i==3:
  x,y=window(d,3,u)
  text(d,(x,y),'系统权限',40)
  for j,l in enumerate(['蓝牙','输入监控','辅助功能']):
   yy=y+70+j*93;rr(d,(x,yy,1734,yy+77),'#F2F6FD',16)
   text(d,(x+15,yy+24),l,28)
   ready=u>2+j*2
   d.ellipse((x+175,yy+32,x+187,yy+44),fill=GREEN if ready else ORANGE)
   text(d,(x+195,yy+25),'已开启' if ready else '未开启',24)
   rr(d,(x+330,yy+20,1714,yy+58),'#E0E5ED',10)
   center(d,x+441,yy+25,'打开蓝牙设置' if j==0 else '打开系统设置',24)
  rr(d,(x,y+364,1734,y+469),'#F2F6FD',16)
  text(d,(x+15,y+377),'虚拟麦克风驱动',28)
  text(d,(x+15,y+425),'已检测到兼容麦克风',24,GREEN)
 elif i==4:
  x,y=window(d,0,u)
  rr(d,(1140,314,1390,795),'#F2F6FD',18)
  center(d,1265,339,'小米遥控器 2 Pro',24)
  center(d,1265,384,'正在连接…' if u<4 else '已连接',28,GREEN)
  remote(d,1210,435,u,False,.9)
  rr(d,(1410,314,1754,616),'#F2F6FD',18)
  text(d,(1430,340),'语音输出',32)
  text(d,(1430,405),'Voice Input Buddy Mic',24)
  text(d,(1430,470),'增益',28)
  d.line((1435,526,1715,526),fill=LINE,width=7)
  d.ellipse((1530,512,1558,540),fill=BLUE)
  text(d,(1430,565),'刷新音频设备',24,BLUE)
  center(d,1578,706,'语音已就绪',32,GREEN)
 elif i==5:
  x,y=window(d,0,u);text(d,(x,y),'语音输出',40)
  rr(d,(x,y+76,1735,y+229),'#EDF3FC',18)
  text(d,(x+20,y+92),'Voice Input Buddy Mic',28,BLUE)
  text(d,(x+20,y+152),'增益',28)
  d.line((x+115,y+178,1660,y+178),fill=LINE,width=7)
  d.ellipse((1432,y+164,1460,y+192),fill=BLUE)
  rr(d,(x,y+259,1735,y+362),'#EDF3FC',18)
  text(d,(x+20,y+275),'输入工具的麦克风',28)
  text(d,(x+20,y+317),'Voice Input Buddy Mic',28,BLUE)
  center(d,1442,y+409,'两边保持一致',32,GREEN)
 elif i==6:
  x,y=window(d,1,u)
  text(d,(1140,311),'按键映射',32)
  text(d,(1305,319),'自定义按键',24)
  rr(d,(1456,318,1512,345),GREEN,14)
  d.ellipse((1485,321,1508,342),fill='white')
  rr(d,(1140,367,1750,409),'#F2F6FD',10)
  text(d,(1155,374),'遥控器：小米蓝牙遥控器 2 Pro',24)
  remote(d,1386,443,u,False,.86)
  for j,(label,action,xx,yy) in enumerate([
   ('电源键','Escape',1140,449),('上键','↑',1140,560),
   ('返回键','删除',1140,671),('语音键','Fn/地球键',1505,449),
   ('确定键','Return',1505,560),('下键','↓',1505,671)]):
   rr(d,(xx,yy,xx+230,yy+94),'#DCE9FF' if label=='确定键' else '#F2F6FD',12)
   text(d,(xx+10,yy+7),label,24)
   if label=='语音键':
    text(d,(xx+10,yy+45),'语音触发键',24,BLUE)
   else:
    for k,gesture in enumerate(['单击','双击','长按']):
     center(d,xx+40+k*75,yy+38,gesture,24,'#758398')
     center(d,xx+40+k*75,yy+67,action if k==0 else '—',20)
 elif i==7:
  x,y=window(d,2,u)
  text(d,(x,y),'输入法与语音工具集成',32)
  rr(d,(x,y+56,1735,y+167),'#EDF3FC',18)
  text(d,(x+16,y+70),'当前集成：微信输入法',28,BLUE)
  text(d,(x+16,y+119),'语音输出：Voice Input Buddy Mic',24)
  for j,label in enumerate(['豆包输入法','微信输入法','Typeless','Vokie','VoiceCursor','其他语音工具']):
   xx=x+(j%2)*294;yy=y+184+(j//2)*82
   rr(d,(xx,yy,xx+280,yy+73),'#DCE9FF' if j==1 else '#F2F6FD',12)
   text(d,(xx+12,yy+5),label,24,BLUE if j==1 else INK)
   text(d,(xx+12,yy+39),'通过向导配置并测试',24)
   if j==1:d.ellipse((xx+249,yy+12,xx+263,yy+26),fill=BLUE)
  text(d,(x,y+439),'语音触发键：Fn/地球键',24,BLUE)
 elif i==8:
  rr(d,(955,306,1790,817),'white',30,LINE)
  text(d,(1000,345),'文本输入框',32)
  rr(d,(996,410,1748,605),'#F4F7FD',18)
  phrase='明天下午三点，讨论新项目。'
  if u>=7:
   n=min(len(phrase),int((u-7)*10)+1);text(d,(1025,478),phrase[:n],40)
  else:
   text(d,(1025,478),'请开始说话…',40,'#AAB3C0')
  remote(d,1013,656,u,2<u<7,.40)
  for j in range(32):
   amp=(18+16*math.sin(j*.8+u*8)) if 2<u<7 else 3
   xx=1160+j*15;d.line((xx,715-amp,xx,715+amp),fill=GREEN,width=6)
  text(d,(1160,760),'按住语音键' if u<7 else '松开，等待识别结果',28,BLUE)
 else:
  rr(d,(978,310,1780,807),'white',35,LINE)
  center(d,1380,371,'让语音更强大',48,BLUE)
  center(d,1380,477,'Voice Input Buddy',40)
  center(d,1380,569,'voice.zfdang.com',48,BLUE)
  center(d,1380,695,'从设置向导开始',32)
 # Voice subtitles: readable, synchronized to the per-scene narration.
 rr(d,(76,886,1844,1036),'#253449',24)
 lines=wrap(d,scenes[i][3],32,1700)
 # Show successive short subtitle chunks rather than an entire paragraph.
 chunks=subtitle_chunks(scenes[i][3])
 spoken=voice_lengths[i] if voice_lengths else 11.5
 position=min(1,u/spoken)*sum(len(c) for c in chunks)
 offset=0; chunk=chunks[-1]
 for c in chunks:
  offset+=len(c)
  if position < offset: chunk=c; break
 for k,l in enumerate(wrap(d,chunk,36,1670)):center(d,W/2,920+k*44,l,36,'white')
 text(d,(96,849),'卡通操作示意  ·  macOS',24,'#8793A5')
 text(d,(1630,849),f'{i+1:02d} / 10',24,'#8793A5')
 rr(d,(76,1069,1844,1077),'#DFE7F2',4)
 rr(d,(76,1069,76+1768*total/120,1077),BLUE,4)
 fade=min(1,u/.3,(12-u)/.3)
 if fade<1:im=Image.blend(Image.new('RGB',(W,H),BG),im,fade)
 return im

voice_lengths=[]
def subtitle_chunks(narration):
 pieces=re.findall(r'[^。！？]+[。！？]?',narration)
 chunks=[]
 for p in pieces:
  if len(p)<=42:chunks.append(p)
  else:
   parts=re.findall(r'[^，]+，?',p); current=''
   for part in parts:
    if len(current+part)>42 and current:chunks.append(current);current=''
    current+=part
   if current:chunks.append(current)
 return chunks

def stamp(seconds):
 ms=int(seconds*1000);return f'{ms//3600000:02}:{ms//60000%60:02}:{ms//1000%60:02},{ms%1000:03}'

