from pathlib import Path
import asyncio, json, subprocess, importlib.util, bisect
import edge_tts
import hashlib
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'dist/videos/source';BASE.mkdir(parents=True,exist_ok=True)
OUT=ROOT/'pages/assets/video'
spec=importlib.util.spec_from_file_location('visual',Path(__file__).with_name('visuals.py'));v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)
narrations=[
'语音搭子，把蓝牙遥控器变成电脑上的语音输入按钮。按住说话，松开，就能输入。',
'遥控器收集声音，语音搭子传送音频、模拟快捷键。微信输入法或其他语音工具，再把声音变成文字。',
'在官网下载安装包，一次安装应用和麦克风驱动。安装需要管理员授权。',
'首次启动，跟着向导检查蓝牙、输入监控和辅助功能权限。完成授权后，回到应用，确认每一项状态。',
'以小米蓝牙遥控器二代 Pro 为例。让遥控器进入配对状态，再按向导连接。看到已连接，就可以继续。',
'在语音搭子里，选择语音输出设备 Voice Input Buddy Mic。输入工具的麦克风，也选择同一个设备。声音偏小，再适当增加增益。',
'打开按键映射，选择遥控器，再点选按键。单击、双击和长按可以分别设置。例如，确定键用于回车，返回键用于删除。',
'在输入法集成里，选择微信输入法。按图设置语音快捷键，排除冲突，再核对麦克风，完成语音测试。',
'点击文本输入框，按住语音键，说：明天下午三点，讨论新项目。说完松开，等待输入工具返回文字。识别效果，由所选工具决定。',
'没有声音，检查连接和麦克风。按键无效，检查权限与快捷键。设置里可以重跑向导、检查更新。语音搭子，让语音更强大。']
for i,t in enumerate(narrations):v.scenes[i]=(*v.scenes[i][:3],t)
voice_paths=[BASE/f'{hashlib.sha256(t.encode()).hexdigest()[:16]}.mp3' for t in narrations]
async def voices():
 for i,t in enumerate(narrations):
  path=voice_paths[i]
  if not path.exists():
   for attempt in range(3):
    try:
     await edge_tts.Communicate(t,'zh-CN-XiaoxiaoNeural',rate='+0%').save(str(path));break
    except Exception:
     if attempt==2:raise
  print(f'Generated natural voice {i+1}/10',flush=True)
asyncio.run(voices())
durations=[float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','csv=p=0',str(voice_paths[i])])) for i in range(10)]
print('Natural speech seconds:',sum(durations),durations,flush=True)
if sum(durations)>116:raise RuntimeError('Narration needs shortening, not speeding up')
gap=(120-sum(durations))/10
lengths=[d+gap for d in durations]; boundaries=[0]
for d in lengths:boundaries.append(boundaries[-1]+d)
v.voice_lengths=[durations[i]*12/lengths[i] for i in range(10)]
srt=[]; n=1
for i in range(10):
 parts=v.subtitle_chunks(narrations[i]);offset=0;total=sum(map(len,parts))
 for p in parts:
  start=boundaries[i]+durations[i]*offset/total;offset+=len(p);end=boundaries[i]+durations[i]*offset/total
  srt.append(f'{n}\n{v.stamp(start)} --> {v.stamp(end)}\n{p}\n');n+=1
 subprocess.run(['ffmpeg','-v','error','-y','-i',str(voice_paths[i]),'-af','apad','-t',str(lengths[i]),'-ar','48000','-ac','1',str(BASE/f'natural-{i}.wav')],check=True)
(OUT/'demo.zh-CN.vtt').write_text('WEBVTT\n\n'+'\n'.join(srt).replace(',', '.'))
(BASE/'script-natural.zh-CN.json').write_text(json.dumps({'voice':'zh-CN-XiaoxiaoNeural','scenes':v.scenes,'durations':lengths},ensure_ascii=False,indent=2))
(BASE/'natural-concat.txt').write_text(''.join(f"file '{BASE/f'natural-{i}.wav'}'\n" for i in range(10)))
subprocess.run(['ffmpeg','-v','error','-y','-f','concat','-safe','0','-i',str(BASE/'natural-concat.txt'),'-c:a','pcm_s16le',str(BASE/'natural-narration.wav')],check=True)
video=OUT/'Voice_Input_Buddy_Demo_Natural_zh-CN.mp4'
cmd=['ffmpeg','-v','error','-y','-f','rawvideo','-pix_fmt','rgb24','-s','1920x1080','-r','12','-i','-','-i',str(BASE/'natural-narration.wav'),'-r','24','-c:v','libx264','-preset','fast','-crf','20','-pix_fmt','yuv420p','-c:a','aac','-b:a','160k','-af','loudnorm=I=-16:TP=-1.5:LRA=11','-t','120','-movflags','+faststart',str(video)]
proc=subprocess.Popen(cmd,stdin=subprocess.PIPE);previous=-1
for f in range(1440):
 t=f/12;i=min(9,bisect.bisect_right(boundaries,t)-1);u=(t-boundaries[i])*12/lengths[i]
 proc.stdin.write(v.frame(i,u,t).tobytes())
 if previous!=i:print(f'Rendered natural scene {i+1}/10',flush=True);previous=i
proc.stdin.close();assert proc.wait()==0
print(video,flush=True)

subprocess.run(['ffmpeg','-v','error','-y','-ss','4','-i',str(video),'-frames:v','1',str(OUT/'demo-poster.jpg')],check=True)
