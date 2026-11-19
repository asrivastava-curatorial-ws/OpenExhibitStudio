"""Deterministic optical fixture. Image coordinates and true transforms belong to the fixture."""
import json
import sys
import tempfile
import unittest
from pathlib import Path
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
import calibrate as cal
cv=cal.cvlib()


class Optics:
    def __init__(self,root,proj=(193,127),cam=(249,185),noise=2,variant=0):
        self.root=Path(root);self.root.mkdir(parents=True,exist_ok=True)
        self.size=proj;self.cam=cam
        self.seq=cal.sequence(*proj)
        w,h=proj;cw,ch=cam
        ref=np.float32([[0,0],[w-1,0],[w-1,h-1],[0,h-1]])
        quad=np.float32([[.12,.10],[.91,.15],[.86,.88],[.08,.84]])*[cw,ch]
        if variant==1:quad=np.float32([[.16,.09],[.88,.05],[.94,.80],[.06,.94]])*[cw,ch]
        self.H=cv.getPerspectiveTransform(ref,quad.astype(np.float32))
        self.corners_px=np.float32([[.055*w,.06*h],[.942*w,.075*h],[.935*w,.94*h],[.07*w,.93*h]])
        self.corners=cv.perspectiveTransform(self.corners_px[None],self.H)[0]
        rng=np.random.default_rng(1776+variant)
        for f in self.seq["frames"]:
            img=np.asarray(cal.pattern(f,w,h),float)
            warped=cv.warpPerspective(img,self.H,cam,flags=cv.INTER_LINEAR)
            exposure=22+warped*.77
            if noise:exposure+=rng.normal(0,noise,exposure.shape)
            Image.fromarray(np.clip(exposure,0,255).astype(np.uint8)).save(self.root/f["file"])
        cal.write_json(self.root/"patterns.json",self.seq)

    def solve(self,**kw):
        return cal.solve(self.seq,self.root,self.corners,**kw)


class CalibrationTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)

    def test_integer_gray_decodes_every_native_pixel_without_powers_of_two(self):
        s=cal.generate(self.root,131,69)
        _,_,valid,loc=cal.decode(s,cal.frame_reader(self.root),32,12)
        y,x=np.indices((69,131))
        self.assertTrue(valid.all());np.testing.assert_array_equal(x,loc[0]);np.testing.assert_array_equal(y,loc[1])
        self.assertEqual(s,cal.manifest(self.root/'patterns.json'))

    def test_known_optics_holdout_independent_frames_and_uv_centres(self):
        for i,(proj,cam) in enumerate([((193,127),(249,185)),((257,149),(319,191)),((109,163),(154,242))]):
            with self.subTest(size=proj):
                f=Optics(self.root/str(i),proj,cam,variant=i%2)
                r=f.solve()
                projected=np.asarray(r['warp'])*proj-.5
                err=float(np.linalg.norm(projected-f.corners_px,axis=1).max())
                self.assertLess(err,.35);self.assertGreaterEqual(r['independent_dots']['samples'],16)
                self.assertLess(r['independent_dots']['p95_px'],.6);self.assertGreater(r['spatial_holdout']['samples'],500)
                print(f"OPTICS {proj[0]}x{proj[1]} corner_max={err:.4f} spatial_p95={r['spatial_holdout']['p95_px']:.4f} optical_p95={r['independent_dots']['p95_px']:.4f} marks={r['independent_dots']['samples']}",flush=True)

    def test_moved_camera_at_independent_check_is_rejected(self):
        f=Optics(self.root)
        for p in self.root.glob('verify-*.png'):
            a=np.array(Image.open(p));Image.fromarray(np.roll(a,6,axis=1)).save(p)
        with self.assertRaisesRegex(cal.CalibrationError,'residuals'):f.solve()

    def test_shadow_and_missing_quadrants_are_rejected(self):
        f=Optics(self.root)
        for p in self.root.glob('*.png'):
            a=np.array(Image.open(p));a[:a.shape[0]//2]=26;Image.fromarray(a).save(p)
        with self.assertRaises(cal.CalibrationError):f.solve()

    def test_swapped_inverse_frames_and_bad_manifest_fail(self):
        f=Optics(self.root)
        a,b=self.root/'x05p.png',self.root/'x05n.png'
        x,y=a.read_bytes(),b.read_bytes();a.write_bytes(y);b.write_bytes(x)
        with self.assertRaises(cal.CalibrationError):f.solve()
        s=json.loads((self.root/'patterns.json').read_text());s['frames'].reverse()
        cal.write_json(self.root/'patterns.json',s)
        with self.assertRaises(cal.CalibrationError):cal.manifest(self.root/'patterns.json')

    def test_missing_references_or_resolution_change_fail(self):
        f=Optics(self.root)
        blank=(self.root/'black.png').read_bytes()
        for p in self.root.glob('verify-*.png'):p.write_bytes(blank)
        with self.assertRaisesRegex(cal.CalibrationError,'Independent dot'):f.solve()
        Image.new('L',(45,45)).save(self.root/'y02p.png')
        with self.assertRaisesRegex(cal.CalibrationError,'resolution changed'):f.solve()

    def test_corner_order_and_low_baseline_fail(self):
        f=Optics(self.root)
        with self.assertRaises(cal.CalibrationError):cal.solve(f.seq,self.root,f.corners[[0,2,1,3]])
        white=np.asarray(Image.open(self.root/'black.png'),float)+5
        Image.fromarray(white.astype(np.uint8)).save(self.root/'white.png')
        with self.assertRaisesRegex(cal.CalibrationError,'decoded'):f.solve()

    def test_metric_pose_independent_survey(self):
        rng=np.random.default_rng(88)
        world=rng.uniform([-1,-.8,-.5],[1,.8,.7],(45,3));K=np.float64([[800,0,480],[0,800,300],[0,0,1]])
        rotation=np.array([.17,-.13,.04]);t=np.array([.3,-.1,4.9])
        R=cv.Rodrigues(rotation)[0];local=world@R.T+t
        proj=local@K.T;xy=proj[:,:2]/proj[:,2:]+rng.normal(0,.04,(len(world),2))
        data=dict(points_m=world[:30],pixels=xy[:30],check_points_m=world[30:],check_pixels=xy[30:],intrinsics=K)
        r=cal.pose(data,1)
        self.assertLess(np.linalg.norm(np.asarray(r['position'])+R.T@t),.003)
        self.assertLess(r['holdout']['p95_px'],.20)
        print(f"POSE holdout_p95={r['holdout']['p95_px']:.4f} camera_position_error_m={np.linalg.norm(np.asarray(r['position'])+R.T@t):.6f}",flush=True)
        with self.assertRaises(cal.CalibrationError):cal.pose(dict(data,check_points_m=world[:6],check_pixels=xy[:6]),1)
        with self.assertRaises(cal.CalibrationError):cal.pose(dict(data,check_pixels=xy[30:]+4),1)

    def test_photometric_curve_and_maximum_white(self):
        xy=lambda xs:[[x,2+98*x**2.24] for x in xs]
        d=dict(fit=xy([0,.1,.25,.55,.8,1]),check=xy([.2,.48,.88]),target_white=75)
        r=cal.photometry(d);self.assertAlmostEqual(r['gamma'],2.24,places=10)
        self.assertAlmostEqual(r['gain'][0],73/98);self.assertLess(r['max_fractional_error'],1e-10)
        with self.assertRaises(cal.CalibrationError):cal.photometry(dict(d,target_white=120))
        d['check'][1][1]+=20
        with self.assertRaises(cal.CalibrationError):cal.photometry(d)

class SiteTests(unittest.TestCase):
    def test_independent_site_target_and_deliberate_misalignment(self):
        from commission import check
        uv=np.array([[x,y] for y in [.12,.5,.88] for x in [.13,.51,.86]])
        d=dict(site="test fixture",projector_serial="synthetic",operator="unit test",camera_id="synthetic",capture_time="fixture",
               physical_size_mm=[1500,900],screen_corners=[[10,20],[1010,20],[1010,620],[10,620]],camera_size=[1100,700],
               observed_camera_px=(uv*[1000,600]+[10,20]).tolist(),requested_uv=uv.tolist(),limit_mm=1.5)
        self.assertEqual(check(d)['status'],'within-site-limit')
        d['observed_camera_px'][0][0]+=2
        self.assertEqual(check(d)['status'],'outside-site-limit')
        self.assertAlmostEqual(check(d)['maximum_mm'],3)


if __name__ == '__main__':
    unittest.main()
