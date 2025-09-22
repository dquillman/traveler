from django.shortcuts import render, redirect, get_object_or_404
from django.forms import ModelForm
from .models import Stay

class StayForm(ModelForm):
    class Meta:
        model = Stay
        fields = [
            "photo","park","city","state","check_in","leave","nights",
            "rate_per_night","total","fees","paid","site","rating",
            "elect_extra","latitude","longitude"
        ]

def stay_list(request):
    stays = Stay.objects.all().order_by('-check_in')
    return render(request, 'stays/stay_list.html', {'stays': stays})

def stay_add(request):
    if request.method == 'POST':
        form = StayForm(request.POST, request.FILES)
        if form.is_valid():
            form.save()
            return redirect('stays:list')
    else:
        form = StayForm()
    return render(request, 'stays/stay_form.html', {'form': form, 'mode': 'add'})

def stay_edit(request, pk):
    stay = get_object_or_404(Stay, pk=pk)
    if request.method == 'POST':
        form = StayForm(request.POST, request.FILES, instance=stay)
        if form.is_valid():
            form.save()
            return redirect('stays:list')
    else:
        form = StayForm(instance=stay)
    return render(request, 'stays/stay_form.html', {'form': form, 'mode': 'edit', 'stay': stay})
