using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using System.Runtime.InteropServices;
using System.Windows.Interop;
using Microsoft.Win32;

namespace QuietDesktop.Windows;
public sealed class Settings {
    public string Appearance { get; set; } = "System";
    public string Notes { get; set; } = "";
    public List<string>? Favorites { get; set; }
    public double Zoom { get; set; } = 1;
    public double X { get; set; }
    public double Y { get; set; }
}
public sealed record LaunchItem(string Name, string Path);
public sealed class StateStore {
    public string Root { get; }
    public Settings Data { get; private set; } = new();
    public string PhotoPath => System.IO.Path.Combine(Root, "photo.png");
    public StateStore(string? root = null) {
        Root = root ?? System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "QuietDesktop");
        Directory.CreateDirectory(Root);
        var file = System.IO.Path.Combine(Root, "settings.json");
        if (File.Exists(file)) {
            try { Data = JsonSerializer.Deserialize<Settings>(File.ReadAllText(file)) ?? new(); }
            catch (JsonException) { File.Copy(file, file + ".recovery-" + DateTime.UtcNow.Ticks); }
        }
        if (!new[] {"System", "Light", "Dark"}.Contains(Data.Appearance)) Data.Appearance = "System";
        Data.Zoom = double.IsFinite(Data.Zoom) ? Math.Clamp(Data.Zoom, 1, 4) : 1;
        Data.X = double.IsFinite(Data.X) ? Math.Clamp(Data.X, -1, 1) : 0;
        Data.Y = double.IsFinite(Data.Y) ? Math.Clamp(Data.Y, -1, 1) : 0;
    }
    public void Save() {
        var target = System.IO.Path.Combine(Root, "settings.json");
        File.WriteAllText(target + ".tmp", JsonSerializer.Serialize(Data));
        File.Move(target + ".tmp", target, true);
    }
}
public sealed class PhotoFrame : Border {
    readonly Image picture = new() { Stretch = Stretch.Fill };
    readonly Canvas canvas = new();
    public BitmapSource? Photo { get; private set; }
    public double Zoom = 1, X, Y;
    public PhotoFrame() {
        CornerRadius = new(14); Height = 210; ClipToBounds = true;
        SetResourceReference(BackgroundProperty, "Panel");
        Child = canvas; canvas.Children.Add(picture);
        SizeChanged += (_, _) => Reframe();
    }
    public static (double Width, double Height, double Left, double Top) Bounds(double iw, double ih, double w, double h, double zoom, double x, double y) {
        var scale = Math.Max(w / iw, h / ih) * Math.Clamp(zoom, 1, 4);
        var width = iw * scale; var height = ih * scale;
        return (width, height, (w - width) / 2 + (width - w) / 2 * Math.Clamp(x, -1, 1), (h - height) / 2 + (height - h) / 2 * Math.Clamp(y, -1, 1));
    }
    public void SetPhoto(BitmapSource? image) { Photo = image; picture.Source = image; Reframe(); }
    public void Reframe() {
        Clip = new RectangleGeometry(new Rect(0, 0, Math.Max(0, ActualWidth), Math.Max(0, ActualHeight)), 14, 14);
        if (Photo == null || ActualWidth < 1 || ActualHeight < 1) return;
        var b = Bounds(Photo.PixelWidth, Photo.PixelHeight, ActualWidth, ActualHeight, Zoom, X, Y);
        picture.Width = b.Width; picture.Height = b.Height; Canvas.SetLeft(picture, b.Left); Canvas.SetTop(picture, b.Top);
    }
}
public sealed class DesktopWindow : Window {
    readonly StateStore store;
    readonly StackPanel body = new();
    readonly TextBlock date = new(), clock = new(), greeting = new(), status = new();
    readonly TextBox search = new(), notes = new();
    readonly WrapPanel appsPanel = new();
    readonly TextBlock section = new();
    readonly PhotoFrame frame = new();
    readonly TextBlock photoPrompt = new() { Text = "Choose a photo to make this space yours", HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, FontSize = 12 };
    readonly Button cropButton, removeButton;
    readonly DispatcherTimer tick = new() { Interval = TimeSpan.FromSeconds(1) };
    readonly DispatcherTimer saveTimer = new() { Interval = TimeSpan.FromMilliseconds(500) };
    readonly List<LaunchItem> applications;
    bool allApps, light, fullScreen;
    WindowState oldState;
    public DesktopWindow(StateStore state, bool sample = false) {
        store = state; applications = DiscoverApps();
        Title = "Quiet Desktop"; Width = 1100; Height = 900; MinWidth = 760; MinHeight = 650;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        FontFamily = new("Segoe UI"); FontSize = 14;
        SetResourceReference(BackgroundProperty, "Background"); SetResourceReference(ForegroundProperty, "Ink");
        body.MaxWidth = 1100; body.Margin = new(64, 36, 64, 30);
        Content = new ScrollViewer { Content = body, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalContentAlignment = HorizontalAlignment.Center };
        ApplyTheme(true);
        var header = Row(); header.Children.Add(Text("●  QUIET DESKTOP", 11, "Muted"));
        var controls = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var appearance = new ComboBox { Width = 105, ItemsSource = new[] { "System", "Light", "Dark" }, SelectedItem = store.Data.Appearance, ToolTip = "Appearance" };
        appearance.SelectionChanged += (_, _) => { store.Data.Appearance = appearance.SelectedItem?.ToString() ?? "System"; ApplyTheme(true); Save(); };
        controls.Children.Add(appearance); controls.Children.Add(Button("⛶", ToggleFullScreen, "Full screen · F11")); controls.Children.Add(Button("—", () => WindowState = WindowState.Minimized, "Minimize"));
        header.Children.Add(controls); Grid.SetColumn(controls, 1); body.Children.Add(header);
        var hero = Row(); hero.Margin = new(0, 48, 0, 28); hero.ColumnDefinitions[0].Width = new(1.1, GridUnitType.Star);
        var timeColumn = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        date.FontSize = 14; date.SetResourceReference(TextBlock.ForegroundProperty, "Muted");
        clock.FontSize = 78; clock.FontWeight = FontWeights.ExtraLight; clock.Margin = new(0, 6, 0, 10);
        greeting.FontSize = 15; greeting.SetResourceReference(TextBlock.ForegroundProperty, "Muted");
        timeColumn.Children.Add(date); timeColumn.Children.Add(clock); timeColumn.Children.Add(greeting); hero.Children.Add(timeColumn);
        var photoColumn = new StackPanel { Margin = new(24, 0, 0, 0) }; Grid.SetColumn(photoColumn, 1);
        var photoOverlay = new Grid(); photoOverlay.Children.Add(frame); photoOverlay.Children.Add(photoPrompt); photoPrompt.SetResourceReference(TextBlock.ForegroundProperty, "Muted");
        photoColumn.Children.Add(photoOverlay);
        var photoActions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
        photoActions.Children.Add(Button("Choose photo…", ChoosePhoto));
        cropButton = Button("Crop…", EditCrop); removeButton = Button("Remove", RemovePhoto);
        photoActions.Children.Add(cropButton); photoActions.Children.Add(removeButton); photoColumn.Children.Add(photoActions); hero.Children.Add(photoColumn); body.Children.Add(hero);
        search.FontSize = 16; search.Padding = new(16); search.MinHeight = 52; search.ToolTip = "Find an app · Ctrl K";
        search.TextChanged += (_, _) => RefreshApps(); search.KeyDown += (_, e) => { if (e.Key == Key.Enter) { var app = Filtered().FirstOrDefault(); if (app != null) Launch(app.Path); } };
        var searchLabel = Text("FIND AN APP  ·  CTRL K", 10, "Muted"); searchLabel.Margin = new(0,0,0,8); body.Children.Add(searchLabel); body.Children.Add(search);
        var reach = Row(); reach.Margin = new(0, 28, 0, 14); section.FontSize = 11; section.SetResourceReference(TextBlock.ForegroundProperty, "Muted"); reach.Children.Add(section);
        var reachActions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        reachActions.Children.Add(Button("Edit", EditFavorites)); reachActions.Children.Add(Button("All apps / Favorites", () => { allApps = !allApps; RefreshApps(); })); Grid.SetColumn(reachActions, 1); reach.Children.Add(reachActions); body.Children.Add(reach); body.Children.Add(appsPanel);
        var divider = new Border { Height = 1, Margin = new(0, 26, 0, 28) }; divider.SetResourceReference(Border.BackgroundProperty, "Line"); body.Children.Add(divider);
        var lower = Row(); lower.ColumnDefinitions[0].Width = new(210); var spaces = new StackPanel(); spaces.Children.Add(Text("YOUR SPACES", 10, "Muted"));
        foreach (var pair in new[] { ("Home", Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)), ("Documents", Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments)), ("Downloads", System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads")), ("Desktop", Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory)) }) {
            var path = pair.Item2; var button = Button(pair.Item1 + "  ↗", () => Launch(path)); button.HorizontalAlignment = HorizontalAlignment.Left; spaces.Children.Add(button);
        }
        lower.Children.Add(spaces);
        var noteColumn = new StackPanel { Margin = new(20, 0, 0, 0) }; noteColumn.Children.Add(Text("A LITTLE SPACE TO THINK", 10, "Muted"));
        notes.Text = store.Data.Notes; notes.AcceptsReturn = true; notes.TextWrapping = TextWrapping.Wrap; notes.MinHeight = 130; notes.Padding = new(8); notes.Margin = new(0, 12, 0, 8); notes.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
        notes.TextChanged += (_, _) => { store.Data.Notes = notes.Text; saveTimer.Stop(); saveTimer.Start(); };
        noteColumn.Children.Add(notes); noteColumn.Children.Add(Text("Saved on this PC", 10, "Muted")); Grid.SetColumn(noteColumn, 1); lower.Children.Add(noteColumn); body.Children.Add(lower);
        status.FontSize = 11; status.Margin = new(0, 28, 0, 0); status.SetResourceReference(TextBlock.ForegroundProperty, "Muted"); status.Text = "Less noise. More room.     F11  Full screen  ·  Alt F4  Quit"; body.Children.Add(status);
        saveTimer.Tick += (_, _) => { saveTimer.Stop(); Save(); };
        tick.Tick += (_, _) => { UpdateClock(); ApplyTheme(); }; tick.Start(); UpdateClock();
        KeyDown += (_, e) => { if (e.Key == Key.K && Keyboard.Modifiers == ModifierKeys.Control) { search.Focus(); search.SelectAll(); e.Handled = true; } else if (e.Key == Key.F11) ToggleFullScreen(); else if (e.Key == Key.Escape && fullScreen) ToggleFullScreen(); };
        Closing += (_, _) => { saveTimer.Stop(); store.Data.Notes = notes.Text; Save(); tick.Stop(); };
        if (store.Data.Favorites == null) {
            store.Data.Favorites = new List<string>();
            foreach (var name in new[] { "Edge", "Notepad", "Calculator", "Calendar" }) { var app = applications.FirstOrDefault(a => a.Name.Contains(name, StringComparison.OrdinalIgnoreCase)); if (app != null) store.Data.Favorites.Add(app.Path); }
            Save();
        }
        if (sample) {
            applications.Clear(); applications.AddRange(new[] {new LaunchItem("Edge", "sample-edge"), new LaunchItem("Calendar", "sample-calendar"), new LaunchItem("Notes", "sample-notes")});
            store.Data.Favorites = applications.Select(a => a.Path).ToList();
        }
        RefreshApps(); LoadPhoto();
    }
    static Grid Row() { var g = new Grid(); g.ColumnDefinitions.Add(new ColumnDefinition()); g.ColumnDefinitions.Add(new ColumnDefinition()); return g; }
    public static TextBlock Text(string s, double size = 14, string key = "Ink") { var t = new TextBlock { Text = s, FontSize = size, VerticalAlignment = VerticalAlignment.Center, TextWrapping = TextWrapping.Wrap }; t.SetResourceReference(TextBlock.ForegroundProperty, key); return t; }
    public static Button Button(string title, Action action, string? tip = null) { var b = new Button { Content = title, Margin = new(4), Padding = new(10, 8, 10, 8), ToolTip = tip }; b.Click += (_, _) => action(); return b; }
    void Save() { try { store.Save(); } catch (Exception e) { status.Text = "Couldn’t save changes: " + e.Message; } }
    void UpdateClock() { var now = DateTime.Now; date.Text = now.ToString("dddd, MMMM d"); clock.Text = now.ToString("t"); greeting.Text = now.Hour < 12 ? "A little room for a good morning." : now.Hour < 18 ? "A little room for a clear afternoon." : "A little room to slow down."; }
    void ApplyTheme(bool force = false) {
        bool next;
        try { next = store.Data.Appearance == "Light" || (store.Data.Appearance == "System" && (int?)Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme", 1) != 0); } catch { next = store.Data.Appearance != "Dark"; }
        if (!force && next == light) return; light = next;
        var r = Application.Current.Resources;
        r["Background"] = new SolidColorBrush((Color)ColorConverter.ConvertFromString(light ? "#F0F0E8" : "#131916"));
        r["Ink"] = new SolidColorBrush((Color)ColorConverter.ConvertFromString(light ? "#29312B" : "#E8ECDD"));
        r["Muted"] = new SolidColorBrush((Color)ColorConverter.ConvertFromString(light ? "#606B60" : "#A3AE9D"));
        r["Panel"] = new SolidColorBrush((Color)ColorConverter.ConvertFromString(light ? "#E3E7DD" : "#222B24")); r["Line"] = r["Panel"];
        var buttonStyle = new Style(typeof(Button)); buttonStyle.Setters.Add(new Setter(Control.BackgroundProperty, r["Panel"])); buttonStyle.Setters.Add(new Setter(Control.ForegroundProperty, r["Ink"])); buttonStyle.Setters.Add(new Setter(Control.BorderThicknessProperty, new Thickness(0))); r[typeof(Button)] = buttonStyle;
        var boxStyle = new Style(typeof(TextBox)); boxStyle.Setters.Add(new Setter(Control.BackgroundProperty, r["Panel"])); boxStyle.Setters.Add(new Setter(Control.ForegroundProperty, r["Ink"])); boxStyle.Setters.Add(new Setter(Control.BorderBrushProperty, r["Panel"])); boxStyle.Setters.Add(new Setter(TextBox.CaretBrushProperty, r["Ink"])); r[typeof(TextBox)] = boxStyle;
    }
    public static List<LaunchItem> DiscoverApps() {
        var result = new List<LaunchItem>();
        foreach (var root in new[] { Environment.GetFolderPath(Environment.SpecialFolder.Programs), Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms) }) {
            if (!Directory.Exists(root)) continue;
            var pending = new Stack<string>(); pending.Push(root);
            while (pending.Count > 0) { var folder = pending.Pop(); try {
                foreach (var file in Directory.EnumerateFiles(folder, "*.lnk")) result.Add(new LaunchItem(System.IO.Path.GetFileNameWithoutExtension(file), file));
                foreach (var child in Directory.EnumerateDirectories(folder)) if ((File.GetAttributes(child) & FileAttributes.ReparsePoint) == 0) pending.Push(child);
            } catch (UnauthorizedAccessException) {} catch (IOException) {} }
        }
        result.Add(new("File Explorer", System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "explorer.exe")));
        return result.GroupBy(a => a.Name, StringComparer.OrdinalIgnoreCase).Select(g => g.First()).OrderBy(a => a.Name).ToList();
    }
    IEnumerable<LaunchItem> Filtered() => applications.Where(a => a.Name.Contains(search.Text.Trim(), StringComparison.OrdinalIgnoreCase));
    void RefreshApps() {
        appsPanel.Children.Clear(); bool browsing = allApps || search.Text.Trim().Length > 0;
        section.Text = browsing ? "APPLICATIONS" : "WITHIN REACH";
        var items = browsing ? Filtered() : (store.Data.Favorites ?? []).Select(path => applications.FirstOrDefault(a => a.Path == path)).OfType<LaunchItem>();
        foreach (var app in items) {
            var stack = new StackPanel();
            var icon = IconFor(app.Path);
            if (icon != null) stack.Children.Add(new Image { Source = icon, Width = 32, Height = 32, Margin = new(0, 0, 0, 8) });
            else stack.Children.Add(Text("▣", 28, "Muted"));
            stack.Children.Add(Text(app.Name, 12));
            var b = Button("", () => Launch(app.Path)); b.Content = stack; b.Width = 135; b.MinHeight = 86; b.ToolTip = app.Name; appsPanel.Children.Add(b);
        }
        if (appsPanel.Children.Count == 0) appsPanel.Children.Add(Text(browsing ? "No matching apps. Try another name." : "Choose Edit to add your favorite apps.", 13, "Muted"));
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct ShellInfo { public IntPtr Icon; public int Index; public uint Attributes; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=260)] public string DisplayName; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=80)] public string TypeName; }
    [DllImport("shell32.dll", CharSet=CharSet.Unicode)] static extern IntPtr SHGetFileInfo(string path, uint attributes, ref ShellInfo info, uint size, uint flags);
    [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr icon);
    static BitmapSource? IconFor(string path) {
        var info = new ShellInfo();
        try {
            if(SHGetFileInfo(path,0,ref info,(uint)Marshal.SizeOf<ShellInfo>(),0x100)==IntPtr.Zero || info.Icon==IntPtr.Zero)return null;
            var result=Imaging.CreateBitmapSourceFromHIcon(info.Icon,Int32Rect.Empty,BitmapSizeOptions.FromWidthAndHeight(32,32)); result.Freeze(); return result;
        } catch { return null; } finally { if(info.Icon!=IntPtr.Zero)DestroyIcon(info.Icon); }
    }
    void Launch(string path) { try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); } catch (Exception e) { MessageBox.Show(this, "Couldn’t open this item.\n" + e.Message, "Quiet Desktop"); } }
    void ToggleFullScreen() { if (!fullScreen) { oldState = WindowState; WindowState = WindowState.Normal; WindowStyle = WindowStyle.None; WindowState = WindowState.Maximized; } else { WindowState = WindowState.Normal; WindowStyle = WindowStyle.SingleBorderWindow; WindowState = oldState; } fullScreen = !fullScreen; }
    Window Dialog(string title, UIElement content, double width, double height) { var w = new Window { Title = title, Owner = this, Content = content, Width = width, Height = height, ResizeMode = ResizeMode.NoResize, WindowStartupLocation = WindowStartupLocation.CenterOwner }; w.SetResourceReference(BackgroundProperty, "Background"); w.SetResourceReference(ForegroundProperty, "Ink"); return w; }
    void EditFavorites() {
        var draft = (store.Data.Favorites ?? []).Where(p => applications.Any(a => a.Path == p)).ToList();
        var panel = new StackPanel { Margin = new(24) }; panel.Children.Add(Text("Within Reach", 24)); panel.Children.Add(Text("Choose apps and arrange their order.", 13, "Muted"));
        var selected = new ListBox { Height = 180, Margin = new(0, 15, 0, 8), DisplayMemberPath = "Name" };
        selected.SetResourceReference(Control.BackgroundProperty, "Panel"); selected.SetResourceReference(Control.ForegroundProperty, "Ink"); panel.Children.Add(selected);
        void Refresh() { selected.ItemsSource = draft.Select(p => applications.First(a => a.Path == p)).ToList(); }
        void Move(int by) { var index = selected.SelectedIndex; if (index < 0 || index + by < 0 || index + by >= draft.Count) return; (draft[index], draft[index+by]) = (draft[index+by], draft[index]); Refresh(); selected.SelectedIndex = index + by; }
        var actions = new StackPanel { Orientation = Orientation.Horizontal }; actions.Children.Add(Button("↑ Earlier", () => Move(-1))); actions.Children.Add(Button("↓ Later", () => Move(1))); actions.Children.Add(Button("Remove", () => { if (selected.SelectedItem is LaunchItem item) { draft.Remove(item.Path); Refresh(); } })); panel.Children.Add(actions);
        var find = new TextBox { Margin = new(0, 10, 0, 8), Padding = new(8) }; panel.Children.Add(Text("Find an app to add",12,"Muted")); panel.Children.Add(find);
        var available = new ListBox { Height = 140, DisplayMemberPath = "Name" }; available.SetResourceReference(Control.BackgroundProperty,"Panel"); available.SetResourceReference(Control.ForegroundProperty,"Ink"); panel.Children.Add(available);
        void Filter() => available.ItemsSource = applications.Where(a=>a.Name.Contains(find.Text,StringComparison.OrdinalIgnoreCase)).ToList();
        find.TextChanged += (_,_)=>Filter(); Filter(); Refresh();
        var bottom = new StackPanel { Orientation = Orientation.Horizontal, Margin = new(0,12,0,0) }; var dialog = Dialog("Edit Within Reach",panel,560,680);
        bottom.Children.Add(Button("Add selected",()=>{if(available.SelectedItem is LaunchItem item && !draft.Contains(item.Path)){draft.Add(item.Path);Refresh();}}));
        bottom.Children.Add(Button("Cancel",()=>dialog.Close())); bottom.Children.Add(Button("Save",()=>{store.Data.Favorites=draft;Save();RefreshApps();dialog.Close();})); panel.Children.Add(bottom); dialog.ShowDialog();
    }
    void ChoosePhoto() {
        var picker = new OpenFileDialog { Title = "Choose a photo", Filter = "Images|*.jpg;*.jpeg;*.png;*.bmp;*.gif;*.tif;*.tiff" };
        if (picker.ShowDialog(this) != true) return;
        try {
            var image = new BitmapImage(); image.BeginInit(); image.CacheOption = BitmapCacheOption.OnLoad; image.DecodePixelWidth = 1600; image.UriSource = new Uri(picker.FileName); image.EndInit(); image.Freeze();
            var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(image)); using (var stream = File.Create(store.PhotoPath+".tmp")) encoder.Save(stream); File.Move(store.PhotoPath+".tmp",store.PhotoPath,true);
            store.Data.Zoom = 1; store.Data.X = store.Data.Y = 0; Save(); LoadPhoto();
        } catch (Exception e) { MessageBox.Show(this,"Couldn’t load this photo. Try a JPEG or PNG.\n"+e.Message,"Quiet Desktop"); }
    }
    void LoadPhoto() {
        try {
            BitmapImage? image = null;
            if (File.Exists(store.PhotoPath)) { image = new(); image.BeginInit(); image.CacheOption=BitmapCacheOption.OnLoad; image.UriSource=new Uri(store.PhotoPath); image.EndInit(); image.Freeze(); }
            frame.Zoom=store.Data.Zoom; frame.X=store.Data.X; frame.Y=store.Data.Y; frame.SetPhoto(image);
            photoPrompt.Visibility=image==null?Visibility.Visible:Visibility.Collapsed; cropButton.IsEnabled=removeButton.IsEnabled=image!=null;
        } catch { status.Text="The saved photo couldn’t be loaded. Choose a new photo."; }
    }
    void RemovePhoto() { try { File.Delete(store.PhotoPath); store.Data.Zoom=1;store.Data.X=store.Data.Y=0;Save();LoadPhoto(); } catch(Exception e){MessageBox.Show(this,e.Message,"Couldn’t remove photo");} }
    void EditCrop() {
        if(frame.Photo==null)return;
        var panel=new StackPanel{Margin=new(24)};panel.Children.Add(Text("Frame your photo",24));panel.Children.Add(Text("Zoom and move the image. Your original stays unchanged.",12,"Muted"));
        var preview=new PhotoFrame{Height=252,Width=468,Margin=new(0,18,0,14),Zoom=store.Data.Zoom,X=store.Data.X,Y=store.Data.Y};preview.SetPhoto(frame.Photo);panel.Children.Add(preview);
        Slider AddSlider(string label,double min,double max,double value,Action<double> update){panel.Children.Add(Text(label,12,"Muted"));var slider=new Slider{Minimum=min,Maximum=max,Value=value,Margin=new(0,6,0,14)};slider.ValueChanged+=(_,_)=>{update(slider.Value);preview.Reframe();};panel.Children.Add(slider);return slider;}
        var zoom=AddSlider("Zoom",1,4,preview.Zoom,v=>preview.Zoom=v);var x=AddSlider("Move left / right",-1,1,preview.X,v=>preview.X=v);var y=AddSlider("Move up / down",-1,1,preview.Y,v=>preview.Y=v);
        var dialog=Dialog("Crop photo",panel,540,640);var actions=new StackPanel{Orientation=Orientation.Horizontal};
        actions.Children.Add(Button("Reset",()=>{zoom.Value=1;x.Value=y.Value=0;}));actions.Children.Add(Button("Cancel",()=>dialog.Close()));actions.Children.Add(Button("Save",()=>{store.Data.Zoom=preview.Zoom;store.Data.X=preview.X;store.Data.Y=preview.Y;Save();LoadPhoto();dialog.Close();}));panel.Children.Add(actions);dialog.ShowDialog();
    }
}
public static class Program {
    [STAThread] public static int Main(string[] args) {
        try {
            var app = new Application();
            if(args.Length==2 && args[0]=="--self-test") return SelfTest(app,args[1]);
            return app.Run(new DesktopWindow(new StateStore()));
        } catch(Exception e){MessageBox.Show("Quiet Desktop couldn’t start.\n"+e.Message,"Quiet Desktop");return 1;}
    }
    static int SelfTest(Application app,string directory) {
        Directory.CreateDirectory(directory);var store=new StateStore(System.IO.Path.Combine(directory,"test-data"));store.Data.Notes="A quiet place to start.";store.Data.Appearance="Dark";store.Data.Favorites=["example"];store.Save();
        var loaded=new StateStore(store.Root);if(loaded.Data.Notes!=store.Data.Notes || loaded.Data.Favorites![0]!="example")return 2;
        foreach(var shape in new[]{(400.0,800.0),(1200.0,400.0)}) foreach(var zoom in new[]{1.0,4.0}) foreach(var pos in new[]{-1.0,1.0}) {
            var b=PhotoFrame.Bounds(shape.Item1,shape.Item2,390,210,zoom,pos,pos);
            if(b.Left>0.001 || b.Top>0.001 || b.Left+b.Width<389.999 || b.Top+b.Height<209.999)return 3;
        }
        var window=new DesktopWindow(store,true){Width=1440,Height=1000};window.Show();window.UpdateLayout();
        app.Dispatcher.Invoke(()=>{},DispatcherPriority.ApplicationIdle);
        var content=(FrameworkElement)window.Content;
        window.Content=null;
        var capture=new Border{Width=1440,Height=1000,Background=window.Background,Child=content};
        System.Windows.Documents.TextElement.SetFontFamily(capture,window.FontFamily);System.Windows.Documents.TextElement.SetFontSize(capture,window.FontSize);System.Windows.Documents.TextElement.SetForeground(capture,window.Foreground);
        capture.Measure(new Size(1440,1000));capture.Arrange(new Rect(0,0,1440,1000));capture.UpdateLayout();
        var bitmap=new RenderTargetBitmap(1440,1000,96,96,PixelFormats.Pbgra32);bitmap.Render(capture);
        var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));using(var file=File.Create(System.IO.Path.Combine(directory,"windows-preview.png")))encoder.Save(file);
        window.Close();File.WriteAllText(System.IO.Path.Combine(directory,"checks.json"),"{\"settingsRoundTrip\":true,\"cropNeverShowsGaps\":true,\"nativeWindowRendered\":true}");return 0;
    }
}
