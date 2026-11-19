shader_type canvas_item;
render_mode unshaded;
uniform vec3 row0=vec3(1.,0.,0.);
uniform vec3 row1=vec3(0.,1.,0.);
uniform vec3 row2=vec3(0.,0.,1.);
uniform int geometry=0;
uniform vec4 view_rect=vec4(0.,0.,1.,1.);
uniform vec4 edges=vec4(0.);
uniform float blend_power=1.;
uniform float gamma_value=1.;
uniform float black_level=0.;
uniform vec3 gain=vec3(1.);
uniform vec3 eye=vec3(0.,0.,4.);
uniform vec3 forward_dir=vec3(0.,0.,-1.);
uniform vec3 right_dir=vec3(1.,0.,0.);
uniform vec3 up_dir=vec3(0.,1.,0.);
uniform float radius=2.;
uniform float height_m=2.;
uniform float arc_rad=6.2831853;
uniform float throw_ratio=1.;
uniform float aspect=1.777778;
uniform vec2 lens_shift=vec2(0.);
uniform float longitude=0.;
uniform int pattern=0;
uniform bool masked=false;
uniform bool cubemap_cross=false;
uniform bool mesh_enabled=false;
uniform vec2 mesh_nodes[9];
uniform sampler2D mask_map : filter_linear, repeat_disable;
float ramp(float d,float edge) {
	if(edge<=0.00001)return 1.;
	float f=clamp(d/edge,0.,1.);
	float a=pow(f,blend_power),b=pow(1.-f,blend_power);
	return a/(a+b);
}
vec2 sample_cube(vec2 c,vec2 texel) {
	float lng=(c.x-.5)*TAU, lat=(.5-c.y)*PI;
	vec3 d=vec3(sin(lng)*cos(lat),sin(lat),cos(lng)*cos(lat)),a=abs(d);
	vec2 tile,face;
	if(a.x>=a.y && a.x>=a.z){tile=vec2(d.x>0.?2.:0.,1.);face=vec2(d.x>0.?-d.z:d.z,-d.y)/a.x;}
	else if(a.y>=a.z){tile=vec2(1.,d.y>0.?0.:2.);face=vec2(d.x,d.y>0.?d.z:-d.z)/a.y;}
	else {tile=vec2(d.z>0.?1.:3.,1.);face=vec2(d.z>0.?d.x:-d.x,-d.y)/a.z;}
	vec2 cells=vec2(4.,3.);
	vec2 pad=texel*cells*.5;
	return (tile+clamp(face*.5+.5,pad,1.-pad))/cells;
}
float det2(vec2 a,vec2 b){return a.x*b.y-a.y*b.x;}
vec2 tri_weights(vec2 a,vec2 b,vec2 c,vec2 p){
	vec2 ab=b-a,ac=c-a;float den=det2(ab,ac);
	if(abs(den)<.000001)return vec2(-2.);
	return vec2(det2(p-a,ac),det2(ab,p-a))/den;
}
vec2 mesh_lookup(vec2 p){
	vec2 result=vec2(-1.);
	for(int y=0;y<2;y++){for(int x=0;x<2;x++){
		int i=y*3+x;
		vec2 base=vec2(float(x),float(y))*.5;
		vec2 wz=tri_weights(mesh_nodes[i],mesh_nodes[i+1],mesh_nodes[i+4],p);
		if(wz.x>=-.000001&&wz.y>=-.000001&&wz.x+wz.y<=1.000001)result=base+.5*vec2(wz.x+wz.y,wz.y);
		wz=tri_weights(mesh_nodes[i],mesh_nodes[i+4],mesh_nodes[i+3],p);
		if(wz.x>=-.000001&&wz.y>=-.000001&&wz.x+wz.y<=1.000001)result=base+.5*vec2(wz.x,wz.x+wz.y);
	}}
	return result;
}
void fragment() {
	vec3 h=vec3(UV,1.);
	float den=dot(row2,h);
	vec2 q=vec2(dot(row0,h),dot(row1,h))/(abs(den)<0.00001?0.00001:den);
	bool visible=all(greaterThanEqual(q,vec2(0.)))&&all(lessThanEqual(q,vec2(1.)));
	if(mesh_enabled){q=mesh_lookup(q);visible=visible&&q.x>=0.;}
	vec2 c=view_rect.xy+q*view_rect.zw;
	if (geometry==1 || geometry==2) {
		vec2 off=(q-vec2(.5)+lens_shift)/max(.01,throw_ratio);
		vec3 ray=normalize(forward_dir+right_dir*off.x-up_dir*off.y/aspect);
		vec3 d=ray, p=eye;
		if (geometry==1) { d.y=0.; p.y=0.; }
		float a=dot(d,d),b=dot(p,d),disc=b*b-a*(dot(p,p)-radius*radius);
		visible=visible&&disc>=0.&&a>.000001;
		float root=sqrt(max(0.,disc));
		float t=(-b-root)/max(a,.000001);
		if(t<=0.) t=(-b+root)/max(a,.000001);
		visible=visible&&t>0.;
		vec3 hit=eye+t*ray;
		float lng=atan(hit.x,hit.z);
		if(geometry==2) c=vec2(fract(.5+lng/TAU+longitude/360.),.5-asin(clamp(hit.y/radius,-1.,1.))/PI);
		else { c=vec2(.5+lng/arc_rad,.5-hit.y/height_m); if(arc_rad>6.28316) c.x=fract(c.x); }
	}
	if(geometry==3) {
		vec2 xy=(q-vec2(.5))*2.;
		visible=visible&&length(xy)<=1.;
		c=vec2(fract(.5+atan(xy.x,-xy.y)/TAU+longitude/360.),length(xy)*.5);
	}
	visible=visible&&all(greaterThanEqual(c,vec2(0.)))&&all(lessThanEqual(c,vec2(1.)));
	vec3 col=texture(TEXTURE,cubemap_cross?sample_cube(c,TEXTURE_PIXEL_SIZE):c).rgb;
	if(pattern==1) {
		vec2 grid=abs(fract(c*vec2(24.,12.)+.5)-.5)/max(fwidth(c*vec2(24.,12.)),vec2(.0001));
		col=mix(vec3(.045,.09,.14),vec3(.32,.86,.81),1.-smoothstep(.5,1.7,min(grid.x,grid.y)));
		if(abs(c.x-.5)<.002 || abs(c.y-.5)<.003) col=vec3(1.,.66,.32);
	}
	if(pattern==2){ float bar=floor(q.x*7.); col=vec3(float(bar==0.||bar==1.||bar==4.||bar==5.),float(bar<4.),float(bar==0.||bar==2.||bar==4.||bar==6.)); }
	float fade=ramp(q.x,edges.x)*ramp(1.-q.x,edges.y)*ramp(q.y,edges.z)*ramp(1.-q.y,edges.w);
	col=pow(max(vec3(0.),col*gain),vec3(1./max(.05,gamma_value)));
	col=mix(vec3(black_level),vec3(1.),col)*fade;
	if(masked) col*=texture(mask_map,UV).r;
	COLOR=vec4(visible?col:vec3(0.),1.);
}
